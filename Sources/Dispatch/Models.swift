import Foundation

struct ToolDefinition: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let command: String

    static let `default`: [ToolDefinition] = [
        ToolDefinition(id: "claude", name: "Claude Code", command: "claude"),
        ToolDefinition(id: "codex", name: "Codex", command: "codex"),
        ToolDefinition(id: "opencode", name: "OpenCode", command: "opencode")
    ]
}

enum TerminalApp: String, CaseIterable, Codable, Identifiable {
    case iTerm2
    case terminal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .iTerm2:
            return "iTerm2"
        case .terminal:
            return "Terminal"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .iTerm2:
            return "com.googlecode.iterm2"
        case .terminal:
            return "com.apple.Terminal"
        }
    }
}

enum LayoutPreset: String, CaseIterable, Codable, Identifiable {
    case adaptive
    case balanced
    case wide
    case dense

    var id: String { rawValue }

    var label: String {
        switch self {
        case .adaptive:
            return "Adaptive"
        case .balanced:
            return "Balanced"
        case .wide:
            return "Wide"
        case .dense:
            return "Dense"
        }
    }

    var detail: String {
        switch self {
        case .adaptive:
            return "Auto-fit by count"
        case .balanced:
            return "Two-column focus"
        case .wide:
            return "Three-column spread"
        case .dense:
            return "Maximum windows"
        }
    }
}

struct LaunchRequest: Codable {
    let terminal: TerminalApp
    let layout: LayoutPreset
    let launchItems: [LaunchItem]

    var totalCount: Int {
        launchItems.map(\.count).reduce(0, +)
    }
}

struct LaunchItem: Codable, Hashable {
    let toolID: String
    let directory: String
    let count: Int
}

struct LaunchPreset: Identifiable, Codable {
    let id: UUID
    var name: String
    var request: LaunchRequest
}

struct ActiveSession: Codable {
    let windowIDs: [Int]
    let request: LaunchRequest
    let launchedAt: Date
}

enum StatusLevel {
    case info
    case success
    case error
}

struct StatusMessage {
    let text: String
    let level: StatusLevel
}

enum DispatchError: LocalizedError {
    case validation(String)
    case system(String)
    case appleScript(String)

    var errorDescription: String? {
        switch self {
        case let .validation(message):
            return message
        case let .system(message):
            return message
        case let .appleScript(message):
            return "Terminal automation failed: \(message)"
        }
    }
}

extension LaunchRequest {
    func summary(using tools: [ToolDefinition]) -> String {
        let map = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0.name) })
        let grouped = Dictionary(grouping: launchItems.filter { $0.count > 0 }, by: { $0.toolID })
        let parts: [String] = grouped.keys.sorted().compactMap { key in
            guard let group = grouped[key] else { return nil }
            let total = group.map(\.count).reduce(0, +)
            let toolName = map[key] ?? key
            return "\(total)x \(toolName)"
        }
        if parts.isEmpty {
            return "No tools selected"
        }
        return parts.joined(separator: ", ")
    }
}
