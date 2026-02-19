import Foundation
import DispatchShared

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
    SharedEventLog.appendSilently(line)
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

// Emit "running" event and log before exec replaces this process.
emit(sessionID: sessionID, agentID: agentID, tool: tool, state: "running")
SharedLaunchLog.append("[\(ISO8601DateFormatter().string(from: Date()))] session=\(sessionID) agent=\(agentID) tool=\(tool) dispatch-agent exec")

// Set environment for the tool and any child processes.
setenv("DISPATCH_SESSION_ID", sessionID, 1)
setenv("DISPATCH_AGENT_ID", agentID, 1)
setenv("DISPATCH_TOOL", tool, 1)

// Use execvp to replace this process with `zsh -lc <command>`.
// This gives the tool full TTY ownership (foreground process group),
// which is required for TUI apps like claude, codex, opencode.
// Post-exit lifecycle events ("done"/"blocked") are emitted by the
// calling launch script, which regains control after exec's process exits.
let cArgs: [UnsafeMutablePointer<CChar>?] = [
    strdup("/bin/zsh"),
    strdup("-lc"),
    strdup(command),
    nil
]
execvp("/bin/zsh", cArgs)

// execvp only returns on failure.
let err = String(cString: strerror(errno))
SharedLaunchLog.append("[\(ISO8601DateFormatter().string(from: Date()))] session=\(sessionID) agent=\(agentID) tool=\(tool) exec failed=\(err)")
emit(sessionID: sessionID, agentID: agentID, tool: tool, state: "blocked", reason: "exec failed: \(err)")
fputs("dispatch-agent exec failed: \(err)\n", stderr)
exit(1)
