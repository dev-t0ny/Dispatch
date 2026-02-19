import Foundation

public enum SharedEventLog {
    public static func url() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Dispatch", isDirectory: true)
            .appendingPathComponent("events.log", isDirectory: false)
    }

    public static func ensureDirectory() {
        let dir = url().deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url().path) {
            FileManager.default.createFile(atPath: url().path, contents: nil)
        }
    }

    /// Append a single JSON line to the event log. Throws on failure.
    public static func append(_ line: String) throws {
        let logURL = url()
        ensureDirectory()

        let data = Data((line + "\n").utf8)
        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    /// Append a single JSON line, silently ignoring errors.
    public static func appendSilently(_ line: String) {
        try? append(line)
    }
}
