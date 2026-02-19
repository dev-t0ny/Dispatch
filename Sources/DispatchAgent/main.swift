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

final class PromptDetector {
    private let sessionID: String
    private let agentID: String
    private let tool: String
    private let attentionMatchers: [NSRegularExpression]
    private let resumeMatchers: [NSRegularExpression]

    private var waitingForHuman = false
    private var lastSignalAt = Date.distantPast
    private let cooldown: TimeInterval = 8

    init(sessionID: String, agentID: String, tool: String) {
        self.sessionID = sessionID
        self.agentID = agentID
        self.tool = tool

        attentionMatchers = PromptDetector.buildAttentionMatchers(for: tool)
        resumeMatchers = PromptDetector.buildResumeMatchers(for: tool)
    }

    func consume(line rawLine: String) {
        let line = sanitize(rawLine)
        guard !line.isEmpty else { return }

        if matchesAny(attentionMatchers, in: line) {
            signalNeedsInput(reason: line)
            return
        }

        if waitingForHuman && matchesAny(resumeMatchers, in: line) {
            emit(state: "running", reason: "Agent resumed after input")
            waitingForHuman = false
            lastSignalAt = Date()
        }
    }

    private func signalNeedsInput(reason: String) {
        let now = Date()
        let shouldSend = !waitingForHuman || now.timeIntervalSince(lastSignalAt) > cooldown
        guard shouldSend else { return }

        emit(state: "needs_input", reason: trimmedReason(reason))
        waitingForHuman = true
        lastSignalAt = now
    }

    private func emit(state: String, reason: String?) {
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

    private func sanitize(_ value: String) -> String {
        let ansiRegex = try? NSRegularExpression(pattern: "\\u001B\\[[0-?]*[ -/]*[@-~]")
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let stripped = ansiRegex?.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: "") ?? value
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trimmedReason(_ reason: String) -> String {
        if reason.count <= 140 { return reason }
        let idx = reason.index(reason.startIndex, offsetBy: 140)
        return String(reason[..<idx]) + "..."
    }

    private func matchesAny(_ patterns: [NSRegularExpression], in line: String) -> Bool {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return patterns.contains { regex in
            regex.firstMatch(in: line, options: [], range: range) != nil
        }
    }

    private static func buildAttentionMatchers(for tool: String) -> [NSRegularExpression] {
        var patterns = [
            "(?i)\\[(y\\/n|y\\/N|yes\\/no)\\]",
            "(?i)(press|hit) enter",
            "(?i)waiting for (your )?(input|approval|confirmation)",
            "(?i)need(s)? your (input|approval|confirmation)",
            "(?i)(confirm|approve|allow|continue|proceed)\\?"
        ]

        if tool == "claude" {
            patterns.append("(?i)do you want me to")
        } else if tool == "codex" {
            patterns.append("(?i)select an option")
        } else if tool == "opencode" {
            patterns.append("(?i)requires your input")
        }

        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }

    private static func buildResumeMatchers(for tool: String) -> [NSRegularExpression] {
        var patterns = [
            "(?i)\\b(running|executing|applying|updated|completed|continuing|working|analyzing|writing)\\b"
        ]

        if tool == "claude" {
            patterns.append("(?i)thinking")
        }

        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }
}

final class LogMonitor: @unchecked Sendable {
    private let logURL: URL
    private let detector: PromptDetector
    private var workerThread: Thread?
    private var shouldStop = false
    private var offset: UInt64 = 0
    private var carry = ""

    init(logURL: URL, detector: PromptDetector) {
        self.logURL = logURL
        self.detector = detector
    }

    func start() {
        let thread = Thread { [weak self] in
            self?.loop()
        }
        workerThread = thread
        thread.start()
    }

    func stop() {
        shouldStop = true
    }

    private func loop() {
        while !shouldStop {
            poll()
            usleep(220_000)
        }
        poll()
    }

    private func poll() {
        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seek(toOffset: offset)

        guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
        offset += UInt64(data.count)

        let chunk = String(decoding: data, as: UTF8.self)
        process(chunk: chunk)
    }

    private func process(chunk: String) {
        let text = carry + chunk
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }).map(String.init)

        if text.hasSuffix("\n") || text.hasSuffix("\r") {
            carry = ""
            for line in lines where !line.isEmpty {
                detector.consume(line: line)
            }
        } else {
            carry = lines.last ?? ""
            for line in lines.dropLast() where !line.isEmpty {
                detector.consume(line: line)
            }
        }
    }
}

func usage() {
    let text = """
    dispatch-agent --tool <tool> --session-id <id> --agent-id <id> [--command <shell command>]
    """
    print(text)
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

let command: String?
if let explicit = value(flag: "--command", args: args), !explicit.isEmpty {
    command = explicit
} else if
    let b64 = ProcessInfo.processInfo.environment["DISPATCH_TOOL_COMMAND_B64"],
    let data = Data(base64Encoded: b64),
    let decoded = String(data: data, encoding: .utf8),
    !decoded.isEmpty
{
    command = decoded
} else {
    command = nil
}

guard let command else {
    fputs("dispatch-agent missing command payload\n", stderr)
    usage()
    exit(1)
}

emit(sessionID: sessionID, agentID: agentID, tool: tool, state: "running")

let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("dispatch-agent-\(sessionID)-\(agentID).log", isDirectory: false)
FileManager.default.createFile(atPath: logURL.path, contents: nil)

let detector = PromptDetector(sessionID: sessionID, agentID: agentID, tool: tool)
let monitor = LogMonitor(logURL: logURL, detector: detector)

let child = Process()
child.executableURL = URL(fileURLWithPath: "/usr/bin/script")
child.arguments = ["-q", logURL.path, "/bin/zsh", "-lc", command]
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
    monitor.start()
    child.waitUntilExit()
    monitor.stop()
    usleep(280_000)

    if child.terminationStatus == 0 {
        emit(sessionID: sessionID, agentID: agentID, tool: tool, state: "done")
    } else {
        emit(sessionID: sessionID, agentID: agentID, tool: tool, state: "blocked", reason: "Process exited with code \(child.terminationStatus)")
    }
    try? FileManager.default.removeItem(at: logURL)
    exit(child.terminationStatus)
} catch {
    monitor.stop()
    try? FileManager.default.removeItem(at: logURL)
    emit(sessionID: sessionID, agentID: agentID, tool: tool, state: "blocked", reason: error.localizedDescription)
    fputs("dispatch-agent failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
