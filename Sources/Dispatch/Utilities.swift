import AppKit
import Foundation

struct DisplayTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let geometry: ScreenGeometry

    var cgDisplayID: CGDirectDisplayID? {
        guard let value = UInt32(id) else { return nil }
        return CGDirectDisplayID(value)
    }
}

struct ScreenGeometry: Hashable {
    let frame: CGRect
    let visibleFrame: CGRect

    static func mainDisplay() -> ScreenGeometry? {
        guard let screen = NSScreen.main else { return nil }
        return ScreenGeometry(frame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    static func allDisplays() -> [DisplayTarget] {
        NSScreen.screens.enumerated().map { index, screen in
            let geometry = ScreenGeometry(frame: screen.frame, visibleFrame: screen.visibleFrame)
            let id = screenID(for: screen)
            let name = displayName(for: screen, fallbackIndex: index)
            return DisplayTarget(id: id, name: name, geometry: geometry)
        }
    }

    static func preferredDisplayID() -> String? {
        if let main = NSScreen.main {
            return screenID(for: main)
        }

        return NSScreen.screens.first.map(screenID(for:))
    }

    private static func screenID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return String(number.uint32Value)
        }

        return String(screen.hash)
    }

    private static func displayName(for screen: NSScreen, fallbackIndex: Int) -> String {
        let size = "\(Int(screen.frame.width))x\(Int(screen.frame.height))"
        let base: String
        if #available(macOS 10.15, *) {
            base = screen.localizedName
        } else {
            base = "Display \(fallbackIndex + 1)"
        }
        return "\(base) (\(size))"
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

    static func shellEscapeForDoubleQuotes(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "`", with: "\\`")
        escaped = escaped.replacingOccurrences(of: "$", with: "\\$")
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
