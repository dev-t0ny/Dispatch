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

    static func append(_ line: String) throws {
        let logURL = url()
        let dir = logURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }

        let data = Data((line + "\n").utf8)
        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}

func usage() {
    let text = """
    dispatchctl state <running|needs_input|blocked|done> [--session-id <id>] [--agent-id <id>] [--tool <id>] [--reason <text>]
    """
    print(text)
}

func value(flag: String, args: [String]) -> String? {
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
    return args[index + 1]
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, args[0] == "state" else {
    usage()
    exit(1)
}

let state = args[1]
let allowedStates = Set(["running", "needs_input", "blocked", "done"])
guard allowedStates.contains(state) else {
    fputs("Unsupported state: \(state)\n", stderr)
    usage()
    exit(1)
}

let environment = ProcessInfo.processInfo.environment
let sessionID = value(flag: "--session-id", args: args) ?? environment["DISPATCH_SESSION_ID"]
let agentID = value(flag: "--agent-id", args: args) ?? environment["DISPATCH_AGENT_ID"]
let tool = value(flag: "--tool", args: args) ?? environment["DISPATCH_TOOL"] ?? "unknown"
let reason = value(flag: "--reason", args: args)

guard let sessionID, !sessionID.isEmpty else {
    fputs("Missing session id. Pass --session-id or set DISPATCH_SESSION_ID.\n", stderr)
    exit(1)
}

guard let agentID, !agentID.isEmpty else {
    fputs("Missing agent id. Pass --agent-id or set DISPATCH_AGENT_ID.\n", stderr)
    exit(1)
}

let formatter = ISO8601DateFormatter()
let event = RuntimeEvent(
    sessionID: sessionID,
    agentID: agentID,
    tool: tool,
    state: state,
    reason: reason,
    timestamp: formatter.string(from: Date())
)

do {
    let data = try JSONEncoder().encode(event)
    guard let line = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "dispatchctl", code: 1, userInfo: [NSLocalizedDescriptionKey: "Encoding failed"])
    }
    try EventLog.append(line)
} catch {
    fputs("Failed to write dispatch event: \(error.localizedDescription)\n", stderr)
    exit(1)
}
