import Foundation

struct RuntimeEvent: Codable {
    let sessionID: String
    let agentID: String
    let tool: String
    let state: String
    let reason: String?
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case agentID = "agent_id"
        case tool
        case state
        case reason
        case timestamp
    }
}

enum EventLog {
    static func url() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Dispatch", isDirectory: true)
            .appendingPathComponent("events.log", isDirectory: false)
    }

    static func append(_ line: String) {
        let logURL = url()
        let dir = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }
}

func usage() {
    print("dispatch-agent --tool <tool> --session-id <id> --agent-id <id> [--command <shell command>]")
}

func value(flag: String, args: [String]) -> String? {
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func emit(sessionID: String, agentID: String, tool: String, state: String, reason: String? = nil) {
    let formatter = ISO8601DateFormatter()
    let event = RuntimeEvent(
        sessionID: sessionID,
        agentID: agentID,
        tool: tool,
        state: state,
        reason: reason,
        timestamp: formatter.string(from: Date())
    )

    guard let data = try? JSONEncoder().encode(event), let line = String(data: data, encoding: .utf8) else { return }
    EventLog.append(line)
}

let args = Array(CommandLine.arguments.dropFirst())
guard
    let tool = value(flag: "--tool", args: args),
    let sessionID = value(flag: "--session-id", args: args),
    let agentID = value(flag: "--agent-id", args: args)
else {
    usage()
    exit(1)
}

let explicitCommand = value(flag: "--command", args: args)
let commandFromB64: String? = {
    guard let b64 = ProcessInfo.processInfo.environment["DISPATCH_TOOL_COMMAND_B64"] else { return nil }
    guard let data = Data(base64Encoded: b64) else { return nil }
    return String(data: data, encoding: .utf8)
}()

guard let command = explicitCommand ?? commandFromB64, !command.isEmpty else {
    fputs("dispatch-agent missing command payload\n", stderr)
    usage()
    exit(1)
}

emit(sessionID: sessionID, agentID: agentID, tool: tool, state: "running")

let child = Process()
child.executableURL = URL(fileURLWithPath: "/bin/zsh")
child.arguments = ["-lc", command]
child.standardInput = FileHandle.standardInput
child.standardOutput = FileHandle.standardOutput
child.standardError = FileHandle.standardError

var env = ProcessInfo.processInfo.environment
env["DISPATCH_SESSION_ID"] = sessionID
env["DISPATCH_AGENT_ID"] = agentID
env["DISPATCH_TOOL"] = tool
child.environment = env

do {
    try child.run()
    child.waitUntilExit()
    if child.terminationStatus == 0 {
        emit(sessionID: sessionID, agentID: agentID, tool: tool, state: "done")
    } else {
        emit(sessionID: sessionID, agentID: agentID, tool: tool, state: "blocked", reason: "Process exited with code \(child.terminationStatus)")
    }
    exit(child.terminationStatus)
} catch {
    emit(sessionID: sessionID, agentID: agentID, tool: tool, state: "blocked", reason: error.localizedDescription)
    fputs("dispatch-agent failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
