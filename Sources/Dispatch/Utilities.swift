import AppKit
import Foundation

struct ScreenGeometry {
    let frame: CGRect
    let visibleFrame: CGRect

    static func mainDisplay() -> ScreenGeometry? {
        guard let screen = NSScreen.main else { return nil }
        return ScreenGeometry(frame: screen.frame, visibleFrame: screen.visibleFrame)
    }
}

struct Shell {
    static func singleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    static func appleScriptEscape(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return escaped
    }

    static func executableName(from command: String) -> String {
        command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? command
    }

    static func isExecutableAvailable(_ executable: String) -> Bool {
        if executable.contains("/") {
            return FileManager.default.isExecutableFile(atPath: executable)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [executable]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
