import AppKit
import Foundation

struct LaunchRow: Identifiable, Hashable {
    let id: UUID
    var toolID: String
    var directory: String
    var count: Int
}

@MainActor
final class DispatchViewModel: ObservableObject {
    @Published var selectedTerminal: TerminalApp = .iTerm2
    @Published var layout: LayoutPreset = .adaptive
    @Published var presetName: String = ""
    @Published var presets: [LaunchPreset]
    @Published var status: StatusMessage?
    @Published var launchRows: [LaunchRow]

    let tools: [ToolDefinition]

    private let launchService: LaunchService
    private let store: SessionStore

    init(launchService: LaunchService = LaunchService(), store: SessionStore = SessionStore()) {
        self.launchService = launchService
        self.store = store
        tools = launchService.toolList()
        presets = store.loadPresets().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let defaultDirectory = Self.defaultDirectory()
        let defaultTool = tools.first?.id ?? "claude"
        launchRows = [LaunchRow(id: UUID(), toolID: defaultTool, directory: defaultDirectory, count: 6)]

        if let last = store.loadLastLaunch() {
            apply(request: last)
        }
    }

    var totalInstances: Int {
        launchRows.map(\.count).reduce(0, +)
    }

    func addRow() {
        let defaultTool = tools.first?.id ?? "claude"
        launchRows.append(LaunchRow(id: UUID(), toolID: defaultTool, directory: Self.defaultDirectory(), count: 1))
    }

    func removeRow(_ rowID: UUID) {
        launchRows.removeAll(where: { $0.id == rowID })
        if launchRows.isEmpty {
            addRow()
        }
    }

    func updateTool(rowID: UUID, toolID: String) {
        guard let index = launchRows.firstIndex(where: { $0.id == rowID }) else { return }
        launchRows[index].toolID = toolID
    }

    func updateDirectory(rowID: UUID, directory: String) {
        guard let index = launchRows.firstIndex(where: { $0.id == rowID }) else { return }
        launchRows[index].directory = directory
    }

    func updateCount(rowID: UUID, count: Int) {
        guard let index = launchRows.firstIndex(where: { $0.id == rowID }) else { return }
        launchRows[index].count = max(0, min(24, count))
    }

    func chooseDirectory(for rowID: UUID) {
        guard let index = launchRows.firstIndex(where: { $0.id == rowID }) else { return }
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: NSString(string: launchRows[index].directory).expandingTildeInPath)

        if panel.runModal() == .OK, let url = panel.url {
            launchRows[index].directory = url.path
        }
    }

    func launchCurrent() {
        launch(request: currentRequest())
    }

    func relaunchLast() {
        guard let request = store.loadLastLaunch() else {
            setStatus("No previous launch found.", level: .error)
            return
        }

        apply(request: request)
        launch(request: request)
    }

    func launchPreset(_ preset: LaunchPreset) {
        apply(request: preset.request)
        launch(request: preset.request)
    }

    func savePreset() {
        let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setStatus("Enter a preset name before saving.", level: .error)
            return
        }

        let preset = LaunchPreset(id: UUID(), name: trimmed, request: currentRequest())
        presets.append(preset)
        presets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        store.savePresets(presets)
        presetName = ""
        setStatus("Saved preset '\(trimmed)'.", level: .success)
    }

    func deletePreset(_ preset: LaunchPreset) {
        presets.removeAll(where: { $0.id == preset.id })
        store.savePresets(presets)
        setStatus("Deleted preset '\(preset.name)'.", level: .info)
    }

    func closeLaunched() {
        guard let activeSession = store.loadActiveSession() else {
            setStatus("No active Dispatch-launched windows to close.", level: .info)
            return
        }

        do {
            try launchService.close(session: activeSession)
            store.saveActiveSession(nil)
            setStatus("Closed \(activeSession.windowIDs.count) Dispatch windows.", level: .success)
        } catch {
            setStatus(error.localizedDescription, level: .error)
        }
    }

    private func launch(request: LaunchRequest) {
        guard let screen = ScreenGeometry.mainDisplay() else {
            setStatus("Unable to read display geometry.", level: .error)
            return
        }

        do {
            let session = try launchService.launch(request: request, screen: screen)
            store.saveActiveSession(session)
            store.saveLastLaunch(request)
            setStatus("Launched \(request.summary(using: tools)) via \(request.terminal.label).", level: .success)
        } catch {
            setStatus(error.localizedDescription, level: .error)
        }
    }

    private func apply(request: LaunchRequest) {
        selectedTerminal = request.terminal
        layout = request.layout

        let mappedRows: [LaunchRow] = request.launchItems.map {
            LaunchRow(id: UUID(), toolID: $0.toolID, directory: $0.directory, count: $0.count)
        }

        if mappedRows.isEmpty {
            let defaultTool = tools.first?.id ?? "claude"
            launchRows = [LaunchRow(id: UUID(), toolID: defaultTool, directory: Self.defaultDirectory(), count: 1)]
        } else {
            launchRows = mappedRows
        }
    }

    private func currentRequest() -> LaunchRequest {
        let items = launchRows.compactMap { row -> LaunchItem? in
            guard row.count > 0 else { return nil }
            let trimmedDirectory = row.directory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDirectory.isEmpty else { return nil }
            return LaunchItem(toolID: row.toolID, directory: trimmedDirectory, count: row.count)
        }

        return LaunchRequest(
            terminal: selectedTerminal,
            layout: layout,
            launchItems: items
        )
    }

    private static func defaultDirectory() -> String {
        let preferred = NSString(string: "~/Documents/Dev").expandingTildeInPath
        if FileManager.default.fileExists(atPath: preferred) {
            return "~/Documents/Dev"
        }
        return "~"
    }

    private func setStatus(_ text: String, level: StatusLevel) {
        status = StatusMessage(text: text, level: level)
    }
}
