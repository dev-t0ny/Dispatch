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

    func readSessionContent(windowID: Int, lineCount: Int) throws -> String {
        let script = """
        tell application "Terminal"
            if exists (window id \(windowID)) then
                set tabContent to contents of current tab of window id \(windowID)
                return tabContent
            end if
            return ""
        end tell
        """

        let result = try runner.run(script)
        guard let full = result?.stringValue, !full.isEmpty else { return "" }

        // Return only the last N lines.
        let lines = full.components(separatedBy: .newlines)
        let tail = lines.suffix(lineCount)
        return tail.joined(separator: "\n")
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
