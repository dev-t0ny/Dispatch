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
}
