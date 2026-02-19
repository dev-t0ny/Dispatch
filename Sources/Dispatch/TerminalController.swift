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
                set rowValue to {(id of w), (item 1 of b), (item 2 of b), (item 3 of b), (item 4 of b)}
                set end of snapshotRows to rowValue
            end repeat
            return snapshotRows
        end tell
        """

        return runner.windowSnapshotsValue(from: try runner.run(script))
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

}
