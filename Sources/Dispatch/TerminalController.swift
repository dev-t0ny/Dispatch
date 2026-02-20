import Foundation

final class TerminalController: TerminalControlling {
    let app: TerminalApp = .terminal
    private let runner = AppleScriptRunner()

    func launchWindow(command: String) throws -> Int {
        let escapedCommand = Shell.appleScriptEscape(command)
        // Atomic launch: `do script` without `in` creates a new window and runs
        // the command in it, returning the tab reference. We then get the window
        // id from the containing window — no race with "front window".
        let script = """
        tell application "Terminal"
            activate
            set newTab to do script "\(escapedCommand)"
            set newWindow to window 1 of (every window whose tabs contains newTab)
            return id of newWindow
        end tell
        """

        return try runner.intValue(from: runner.run(script))
    }

    func setBounds(windowID: Int, bounds: WindowBounds) throws {
        let script = """
        tell application "Terminal"
            if exists (window id \(windowID)) then
                set bounds of window id \(windowID) to {\(bounds.left), \(bounds.top), \(bounds.right), \(bounds.bottom)}
            end if
        end tell
        """

        _ = try runner.run(script)
    }

    func closeWindow(windowID: Int) throws {
        let script = """
        tell application "Terminal"
            if exists (window id \(windowID)) then
                close (window id \(windowID))
            end if
        end tell
        """

        _ = try runner.run(script)
    }

    func focusWindow(windowID: Int) throws {
        let script = """
        tell application "Terminal"
            activate
            if exists (window id \(windowID)) then
                set index of window id \(windowID) to 1
            end if
        end tell
        """

        _ = try runner.run(script)
    }

    func listWindowSnapshots() throws -> [TerminalWindowSnapshot] {
        let script = """
        tell application "Terminal"
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

    func detectIdleWindowIDs(among windowIDs: [Int]) throws -> Set<Int> {
        guard !windowIDs.isEmpty else { return [] }

        // Get TTY for each window via AppleScript.
        let ttyMap = try getWindowTTYs(windowIDs: windowIDs)
        guard !ttyMap.isEmpty else { return [] }

        let stringMap = Dictionary(uniqueKeysWithValues: ttyMap.map { (String($0.key), $0.value) })
        let idleKeys = TTYMonitor.detectIdle(ttys: stringMap)
        return Set(idleKeys.compactMap { Int($0) })
    }

    private func getWindowTTYs(windowIDs: [Int]) throws -> [Int: String] {
        guard !windowIDs.isEmpty else { return [:] }

        let windowChecks = windowIDs.map { wid in
            """
                        try
                            if exists (window id \(wid)) then
                                set end of ttyPairs to ("\(wid):" & tty of current tab of window id \(wid))
                            end if
                        end try
            """
        }.joined(separator: "\n")

        let script = """
        tell application "Terminal"
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
        // Use Terminal's custom title property instead of injecting shell commands
        // into the running session, which would corrupt interactive agent tools.
        let decoratedTitle = "[\(tone.label)] \(title)"
        let escapedTitle = Shell.appleScriptEscape(decoratedTitle)

        let script = """
        tell application "Terminal"
            if exists (window id \(windowID)) then
                set custom title of current tab of window id \(windowID) to "\(escapedTitle)"
            end if
        end tell
        """

        _ = try runner.run(script)
    }

}
