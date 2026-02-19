import Foundation

struct DispatchRuntimeEvent: Codable {
    let sessionID: String
    let agentID: String
    let tool: String
    let state: String
    let reason: String?
    let timestamp: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case agentID = "agent_id"
        case tool
        case state
        case reason
        case timestamp
    }
}

enum DispatchEventLog {
    static func fileURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Dispatch", isDirectory: true)
            .appendingPathComponent("events.log", isDirectory: false)
    }

    static func ensureExists() {
        let url = fileURL()
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    static func readLines() -> [String] {
        ensureExists()
        guard let data = try? Data(contentsOf: fileURL()) else { return [] }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}
