import Foundation

/// Monitors TTY devices to detect whether a terminal session's foreground
/// process is idle (waiting for input) or actively working.
///
/// Detection heuristic: when a TUI tool (claude, codex, opencode) is busy,
/// it spawns child processes (node workers, language servers, etc.) in the
/// foreground process group. When it's idle/waiting for user input, the
/// process group contains only the tool itself (1-2 processes).
///
/// This approach works regardless of terminal app and doesn't require
/// shell integration or content scraping.
enum TTYMonitor {

    /// Threshold: if the foreground process group on a TTY has this many or
    /// fewer members, the tool is considered idle / waiting for input.
    private static let idleThreshold = 2

    /// Batch check: given a mapping of [identifier: ttyPath], returns the set
    /// of identifiers whose TTY appears idle.
    static func detectIdle(ttys: [String: String]) -> Set<String> {
        guard !ttys.isEmpty else { return [] }

        // Get all process info in a single `ps` call for efficiency.
        let allProcesses = snapshotProcesses()

        var idleIDs: Set<String> = []
        for (identifier, ttyPath) in ttys {
            let ttyName = ttyPath.replacingOccurrences(of: "/dev/", with: "")
            guard !ttyName.isEmpty else { continue }

            let fgCount = allProcesses.filter { $0.tty == ttyName && $0.isForeground }.count

            if fgCount <= idleThreshold {
                idleIDs.insert(identifier)
            }
        }

        return idleIDs
    }

    // MARK: - Internal

    private struct ProcessInfo {
        let pid: Int
        let tty: String
        let stat: String
        let isForeground: Bool
    }

    /// Snapshot all processes with a TTY in a single `ps` call.
    private static func snapshotProcesses() -> [ProcessInfo] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-eo", "pid,tty,stat"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [ProcessInfo] = []

        for line in output.components(separatedBy: .newlines).dropFirst() { // skip header
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }

            guard parts.count >= 3,
                  let pid = Int(parts[0]) else { continue }

            let tty = parts[1]
            let stat = parts[2]

            guard tty != "??" else { continue } // no TTY

            let isForeground = stat.contains("+")

            results.append(ProcessInfo(
                pid: pid,
                tty: tty,
                stat: stat,
                isForeground: isForeground
            ))
        }

        return results
    }
}
