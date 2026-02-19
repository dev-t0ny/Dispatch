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

enum AgentTone: String, CaseIterable, Codable, Identifiable {
    case slate
    case ocean
    case mint
    case amber
    case rose
    case violet

    var id: String { rawValue }

    var label: String {
        switch self {
        case .slate:
            return "Slate"
        case .ocean:
            return "Ocean"
        case .mint:
            return "Mint"
        case .amber:
            return "Amber"
        case .rose:
            return "Rose"
        case .violet:
            return "Violet"
        }
    }

    var hex: String {
        switch self {
        case .slate:
            return "#64748B"
        case .ocean:
            return "#0284C7"
        case .mint:
            return "#10B981"
        case .amber:
            return "#F59E0B"
        case .rose:
            return "#FB7185"
        case .violet:
            return "#8B5CF6"
        }
    }
}

enum AgentState: String, CaseIterable, Codable, Identifiable {
    case running
    case needsInput
    case blocked
    case done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .running:
            return "Running"
        case .needsInput:
            return "Needs Input"
        case .blocked:
            return "Blocked"
        case .done:
            return "Done"
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
                LaunchItem(
                    toolID: $0.toolID,
                    directory: legacyDirectory,
                    count: $0.count,
                    agentName: Self.defaultAgentName(toolID: $0.toolID),
                    role: "Implementer",
                    objective: "",
                    tone: .ocean,
                    startSlot: nil
                )
            }
            return
        }

        if
            let toolID = try container.decodeIfPresent(String.self, forKey: .toolID),
            let directory = try container.decodeIfPresent(String.self, forKey: .directory),
            let count = try container.decodeIfPresent(Int.self, forKey: .count)
        {
            launchItems = [
                LaunchItem(
                    toolID: toolID,
                    directory: directory,
                    count: count,
                    agentName: Self.defaultAgentName(toolID: toolID),
                    role: "Implementer",
                    objective: "",
                    tone: .ocean,
                    startSlot: nil
                )
            ]
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

    private static func defaultAgentName(toolID: String) -> String {
        switch toolID {
        case "claude":
            return "Claude Agent"
        case "codex":
            return "Codex Agent"
        case "opencode":
            return "OpenCode Agent"
        default:
            return "Agent"
        }
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
    let agentName: String
    let role: String
    let objective: String
    let tone: AgentTone
    let startSlot: Int?

    init(
        toolID: String,
        directory: String,
        count: Int,
        agentName: String = "Agent",
        role: String = "Implementer",
        objective: String = "",
        tone: AgentTone = .ocean,
        startSlot: Int? = nil
    ) {
        self.toolID = toolID
        self.directory = directory
        self.count = count
        self.agentName = agentName
        self.role = role
        self.objective = objective
        self.tone = tone
        self.startSlot = startSlot
    }

    private enum CodingKeys: String, CodingKey {
        case toolID
        case directory
        case count
        case agentName
        case role
        case objective
        case tone
        case startSlot
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolID = try container.decode(String.self, forKey: .toolID)
        directory = try container.decode(String.self, forKey: .directory)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
        agentName = try container.decodeIfPresent(String.self, forKey: .agentName) ?? "Agent"
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "Implementer"
        objective = try container.decodeIfPresent(String.self, forKey: .objective) ?? ""
        tone = try container.decodeIfPresent(AgentTone.self, forKey: .tone) ?? .ocean
        startSlot = try container.decodeIfPresent(Int.self, forKey: .startSlot)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolID, forKey: .toolID)
        try container.encode(directory, forKey: .directory)
        try container.encode(count, forKey: .count)
        try container.encode(agentName, forKey: .agentName)
        try container.encode(role, forKey: .role)
        try container.encode(objective, forKey: .objective)
        try container.encode(tone, forKey: .tone)
        try container.encodeIfPresent(startSlot, forKey: .startSlot)
    }
}

struct LaunchPreset: Identifiable, Codable {
    let id: UUID
    var name: String
    var request: LaunchRequest
}

struct AgentWindow: Identifiable, Codable, Hashable {
    let id: UUID
    let windowID: Int
    let toolID: String
    let directory: String
    let name: String
    let role: String
    let objective: String
    let tone: AgentTone
    let slot: Int?
    let launchedAt: Date
    var state: AgentState
    var lastFocusedAt: Date?
}

struct ActiveSession: Codable {
    var agentWindows: [AgentWindow]
    let request: LaunchRequest
    let launchedAt: Date
    var focusHistory: [UUID]

    var windowIDs: [Int] {
        agentWindows.map(\.windowID)
    }

    init(agentWindows: [AgentWindow], request: LaunchRequest, launchedAt: Date = Date(), focusHistory: [UUID] = []) {
        self.agentWindows = agentWindows
        self.request = request
        self.launchedAt = launchedAt
        self.focusHistory = focusHistory
    }

    private enum CodingKeys: String, CodingKey {
        case agentWindows
        case request
        case launchedAt
        case focusHistory
        case windowIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = try container.decode(LaunchRequest.self, forKey: .request)
        launchedAt = try container.decodeIfPresent(Date.self, forKey: .launchedAt) ?? Date()
        focusHistory = try container.decodeIfPresent([UUID].self, forKey: .focusHistory) ?? []

        if let windows = try container.decodeIfPresent([AgentWindow].self, forKey: .agentWindows), !windows.isEmpty {
            agentWindows = windows
            return
        }

        let legacyWindowIDs = try container.decodeIfPresent([Int].self, forKey: .windowIDs) ?? []
        agentWindows = Self.makeFallbackAgents(windowIDs: legacyWindowIDs, request: request, launchedAt: launchedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(agentWindows, forKey: .agentWindows)
        try container.encode(request, forKey: .request)
        try container.encode(launchedAt, forKey: .launchedAt)
        try container.encode(focusHistory, forKey: .focusHistory)
    }

    private static func makeFallbackAgents(windowIDs: [Int], request: LaunchRequest, launchedAt: Date) -> [AgentWindow] {
        let expandedItems: [LaunchItem] = request.launchItems.flatMap { item in
            Array(repeating: item, count: max(0, item.count))
        }

        return windowIDs.enumerated().map { index, windowID in
            let item = index < expandedItems.count ? expandedItems[index] : nil
            return AgentWindow(
                id: UUID(),
                windowID: windowID,
                toolID: item?.toolID ?? "unknown",
                directory: item?.directory ?? "",
                name: item?.agentName ?? "Agent \(index + 1)",
                role: item?.role ?? "Implementer",
                objective: item?.objective ?? "",
                tone: item?.tone ?? .ocean,
                slot: item?.startSlot,
                launchedAt: launchedAt,
                state: .running,
                lastFocusedAt: nil
            )
        }
    }
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

extension AgentWindow {
    var title: String {
        "\(name) • \(role)"
    }

    var badge: String {
        let objectiveLabel = objective.isEmpty ? "No objective" : objective
        return "\(state.label) | \(objectiveLabel)"
    }
}
