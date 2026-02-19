import Foundation

final class ITermController: TerminalControlling {
    let app: TerminalApp = .iTerm2
    private let runner = AppleScriptRunner()

    func launchWindow(command: String) throws -> Int {
        let escapedCommand = Shell.appleScriptEscape(command)
        // Two-step launch: create the window first, wait until the shell prompt
        // is ready (is_at_shell_prompt), then write the command. This avoids
        // the race where `write text` is swallowed because the session's shell
        // hasn't finished initializing.
        let script = """
        tell application "iTerm2"
            activate
            set newWindow to (create window with default profile)
            tell current session of current tab of newWindow
                set retryCount to 0
                repeat while retryCount < 40
                    try
                        if is at shell prompt then exit repeat
                    end try
                    delay 0.05
                    set retryCount to retryCount + 1
                end repeat
                write text "\(escapedCommand)"
            end tell
            return (id of newWindow)
        end tell
        """

        return try runner.intValue(from: runner.run(script))
    }

    func setBounds(windowID: Int, bounds: WindowBounds) throws {
        let script = """
        tell application "iTerm2"
            if exists (window id \(windowID)) then
                set bounds of window id \(windowID) to {\(bounds.left), \(bounds.top), \(bounds.right), \(bounds.bottom)}
            end if
        end tell
        """

        _ = try runner.run(script)
    }

    func closeWindow(windowID: Int) throws {
        let script = """
        tell application "iTerm2"
            if exists (window id \(windowID)) then
                close (window id \(windowID))
            end if
        end tell
        """

        _ = try runner.run(script)
    }

    func focusWindow(windowID: Int) throws {
        let script = """
        tell application "iTerm2"
            activate
            if exists (window id \(windowID)) then
                select (window id \(windowID))
            end if
        end tell
        """

        _ = try runner.run(script)
    }

    func listWindowSnapshots() throws -> [TerminalWindowSnapshot] {
        let script = """
        tell application "iTerm2"
            set snapshotRows to {}
            repeat with w in windows
                set b to bounds of w
                set rowValue to {(id of w), (item 1 of b), (item 2 of b), (item 3 of b), (item 4 of b)}
                set end of snapshotRows to rowValue
            end repeat
            return snapshotRows
        end tell
        """

        return runner.windowSnapshotsValue(from: try runner.run(script))
    }

    func readSessionContent(windowID: Int, lineCount: Int) throws -> String {
        let script = """
        tell application "iTerm2"
            if exists (window id \(windowID)) then
                tell current session of current tab of window id \(windowID)
                    set totalRows to number of rows
                    set startRow to totalRows - \(lineCount)
                    if startRow < 0 then set startRow to 0
                    set screenText to contents
                    return screenText
                end tell
            end if
            return ""
        end tell
        """

        let result = try runner.run(script)
        return result?.stringValue ?? ""
    }

    func detectIdleWindowIDs(among windowIDs: [Int]) throws -> Set<Int> {
        guard !windowIDs.isEmpty else { return [] }

        // Get the TTY device path for each window in a single AppleScript call.
        let ttyMap = try getWindowTTYs(windowIDs: windowIDs)
        guard !ttyMap.isEmpty else { return [] }

        // Use TTY process monitoring to detect which sessions are idle.
        // Key is window ID as string, value is TTY path.
        let stringMap = Dictionary(uniqueKeysWithValues: ttyMap.map { (String($0.key), $0.value) })
        let idleKeys = TTYMonitor.detectIdle(ttys: stringMap)

        return Set(idleKeys.compactMap { Int($0) })
    }

    /// Batch-fetch TTY device paths for the given window IDs in a single AppleScript call.
    func getWindowTTYs(windowIDs: [Int]) throws -> [Int: String] {
        guard !windowIDs.isEmpty else { return [:] }

        let windowChecks = windowIDs.map { wid in
            """
                        try
                            if exists (window id \(wid)) then
                                tell current session of current tab of window id \(wid)
                                    set end of ttyPairs to ("\(wid):" & tty)
                                end tell
                            end if
                        end try
            """
        }.joined(separator: "\n")

        let script = """
        tell application "iTerm2"
            set ttyPairs to {}
        \(windowChecks)
            set resultText to ""
            repeat with p in ttyPairs
                if resultText is not "" then set resultText to resultText & ","
                set resultText to resultText & p
            end repeat
            return resultText
        end tell
        """

        let result = try runner.run(script)
        let raw = result?.stringValue ?? ""
        guard !raw.isEmpty else { return [:] }

        // Parse "12345:/dev/ttys003,12346:/dev/ttys004"
        var map: [Int: String] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  let wid = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
            map[wid] = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        return map
    }

    func applyIdentity(windowID: Int, title: String, badge: String, tone: AgentTone) throws {
        let escapedTitle = Shell.appleScriptEscape(title)
        let script = """
        tell application "iTerm2"
            if exists (window id \(windowID)) then
                tell current session of current tab of window id \(windowID)
                    set name to "\(escapedTitle)"
                end tell
            end if
        end tell
        """

        _ = try runner.run(script)
    }
}
