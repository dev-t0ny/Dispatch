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
    let screenIDs: [String]

    var totalCount: Int {
        launchItems.map(\.count).reduce(0, +)
    }

    init(terminal: TerminalApp, layout: LayoutPreset, launchItems: [LaunchItem], screenIDs: [String] = []) {
        self.terminal = terminal
        self.layout = layout
        self.launchItems = launchItems
        self.screenIDs = screenIDs
    }

    private enum CodingKeys: String, CodingKey {
        case terminal
        case layout
        case launchItems
        case screenIDs

        case directory
        case toolLaunches
        case toolID
        case count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        terminal = try container.decodeIfPresent(TerminalApp.self, forKey: .terminal) ?? .iTerm2
        layout = try container.decodeIfPresent(LayoutPreset.self, forKey: .layout) ?? .adaptive
        screenIDs = try container.decodeIfPresent([String].self, forKey: .screenIDs) ?? []

        if let items = try container.decodeIfPresent([LaunchItem].self, forKey: .launchItems), !items.isEmpty {
            launchItems = items
            return
        }

        if
            let legacyDirectory = try container.decodeIfPresent(String.self, forKey: .directory),
            let legacyToolLaunches = try container.decodeIfPresent([LegacyToolLaunch].self, forKey: .toolLaunches)
        {
            launchItems = legacyToolLaunches.map {
                LaunchItem(toolID: $0.toolID, directory: legacyDirectory, count: $0.count)
            }
            return
        }

        if
            let toolID = try container.decodeIfPresent(String.self, forKey: .toolID),
            let directory = try container.decodeIfPresent(String.self, forKey: .directory),
            let count = try container.decodeIfPresent(Int.self, forKey: .count)
        {
            launchItems = [LaunchItem(toolID: toolID, directory: directory, count: count)]
            return
        }

        launchItems = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(terminal, forKey: .terminal)
        try container.encode(layout, forKey: .layout)
        try container.encode(launchItems, forKey: .launchItems)
        try container.encode(screenIDs, forKey: .screenIDs)
    }
}

private struct LegacyToolLaunch: Codable {
    let toolID: String
    let count: Int
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
