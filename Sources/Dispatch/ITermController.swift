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

    func listWindowIDs() throws -> [Int] {
        let script = """
        tell application \"iTerm2\"
            return id of every window
        end tell
        """

        return try runner.intArrayValue(from: runner.run(script))
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
}
