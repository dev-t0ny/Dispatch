import Foundation

final class TerminalController: TerminalControlling {
    let app: TerminalApp = .terminal
    private let runner = AppleScriptRunner()

    func launchWindow(command: String) throws -> Int {
        let escapedCommand = Shell.appleScriptEscape(command)
        let script = """
        tell application \"Terminal\"
            activate
            do script \"\"
            delay 0.08
            do script \"\(escapedCommand)\" in front window
            return id of front window
        end tell
        """

        return try runner.intValue(from: runner.run(script))
    }

    func setBounds(windowID: Int, bounds: WindowBounds) throws {
        let script = """
        tell application \"Terminal\"
            if exists (window id \(windowID)) then
                set bounds of window id \(windowID) to {\(bounds.left), \(bounds.top), \(bounds.right), \(bounds.bottom)}
            end if
        end tell
        """

        _ = try runner.run(script)
    }

    func closeWindow(windowID: Int) throws {
        let script = """
        tell application \"Terminal\"
            if exists (window id \(windowID)) then
                close (window id \(windowID))
            end if
        end tell
        """

        _ = try runner.run(script)
    }

    func focusWindow(windowID: Int) throws {
        let script = """
        tell application \"Terminal\"
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
        tell application \"Terminal\"
            set snapshotRows to {}
            repeat with w in windows
                set b to bounds of w
                set end of snapshotRows to ((id of w as string) & "," & (item 1 of b as string) & "," & (item 2 of b as string) & "," & (item 3 of b as string) & "," & (item 4 of b as string))
            end repeat
            return snapshotRows
        end tell
        """

        let rows = runner.stringArrayValue(from: try runner.run(script))
        return rows.compactMap(parseSnapshot)
    }

    func applyIdentity(windowID: Int, title: String, badge: String, tone: AgentTone) throws {
        let decoratedTitle = "[\(tone.label)] \(title)"
        let titleCommand = "printf '\\e]0;\(Shell.shellEscapeForDoubleQuotes(decoratedTitle))\\a'"
        let escapedCommand = Shell.appleScriptEscape(titleCommand)
        let escapedBadge = Shell.appleScriptEscape(badge)

        let script = """
        tell application \"Terminal\"
            if exists (window id \(windowID)) then
                do script \"\(escapedCommand)\" in window id \(windowID)
                do script \"printf '\\n[Dispatch] \(escapedBadge)\\n'\" in window id \(windowID)
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
