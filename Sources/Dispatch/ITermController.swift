import Foundation

final class ITermController: TerminalControlling {
    let app: TerminalApp = .iTerm2
    private let runner = AppleScriptRunner()

    func launchWindow(command: String) throws -> Int {
        let escapedCommand = Shell.appleScriptEscape(command)
        let script = """
        tell application \"iTerm2\"
            activate
            set newWindow to (create window with default profile command \"\(escapedCommand)\")
            return (id of newWindow)
        end tell
        """

        return try runner.intValue(from: runner.run(script))
    }

    func setBounds(windowID: Int, bounds: WindowBounds) throws {
        let script = """
        tell application \"iTerm2\"
            if exists (window id \(windowID)) then
                set bounds of window id \(windowID) to {\(bounds.left), \(bounds.top), \(bounds.right), \(bounds.bottom)}
            end if
        end tell
        """

        _ = try runner.run(script)
    }

    func closeWindow(windowID: Int) throws {
        let script = """
        tell application \"iTerm2\"
            if exists (window id \(windowID)) then
                close (window id \(windowID))
            end if
        end tell
        """

        _ = try runner.run(script)
    }

    func focusWindow(windowID: Int) throws {
        let script = """
        tell application \"iTerm2\"
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
        tell application \"iTerm2\"
            set snapshotRows to {}
            repeat with w in windows
                set b to bounds of w
                set rowValue to (((id of w) as text) & "," & ((item 1 of b) as text) & "," & ((item 2 of b) as text) & "," & ((item 3 of b) as text) & "," & ((item 4 of b) as text))
                set end of snapshotRows to rowValue
            end repeat
            return snapshotRows
        end tell
        """

        let rows = runner.stringArrayValue(from: try runner.run(script))
        return rows.compactMap(parseSnapshot)
    }

    func applyIdentity(windowID: Int, title: String, badge: String, tone: AgentTone) throws {
        let escapedTitle = Shell.appleScriptEscape(title)
        let escapedBadge = Shell.appleScriptEscape("[\(tone.label)] \(badge)")
        let script = """
        tell application \"iTerm2\"
            if exists (window id \(windowID)) then
                tell current session of current tab of window id \(windowID)
                    set name to \"\(escapedTitle)\"
                    set badge text to \"\(escapedBadge)\"
                end tell
            end if
        end tell
        """

        _ = try runner.run(script)
    }

    private func parseSnapshot(_ row: String) -> TerminalWindowSnapshot? {
        let parts = row.split(separator: ",").map(String.init)
        guard parts.count == 5 else { return nil }
        guard
            let id = Int(parts[0]),
            let left = Int(parts[1]),
            let top = Int(parts[2]),
            let right = Int(parts[3]),
            let bottom = Int(parts[4])
        else {
            return nil
        }

        return TerminalWindowSnapshot(windowID: id, left: left, top: top, right: right, bottom: bottom)
    }
}
