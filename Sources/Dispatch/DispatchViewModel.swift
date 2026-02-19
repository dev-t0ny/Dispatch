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
    @Published var availableScreens: [DisplayTarget]
    @Published var selectedScreenIDs: Set<String>

    let tools: [ToolDefinition]

    private let launchService: LaunchService
    private let store: SessionStore

    init(launchService: LaunchService = LaunchService(), store: SessionStore = SessionStore()) {
        self.launchService = launchService
        self.store = store
        tools = launchService.toolList()
        presets = store.loadPresets().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        availableScreens = ScreenGeometry.allDisplays()
        selectedScreenIDs = []

        let defaultDirectory = Self.defaultDirectory()
        let defaultTool = tools.first?.id ?? "claude"
        launchRows = [LaunchRow(id: UUID(), toolID: defaultTool, directory: defaultDirectory, count: 6)]

        refreshDisplays(preferredIDs: [])

        if let last = store.loadLastLaunch() {
            apply(request: last)
        }
    }

    var totalInstances: Int {
        launchRows.map(\.count).reduce(0, +)
    }

    func addTerminal() {
        let defaultTool = tools.first?.id ?? "claude"
        launchRows.append(LaunchRow(id: UUID(), toolID: defaultTool, directory: Self.defaultDirectory(), count: 1))
    }

    func setTotalInstances(_ total: Int) {
        let clampedTotal = max(0, min(240, total))

        if launchRows.isEmpty {
            let defaultTool = tools.first?.id ?? "claude"
            launchRows = [LaunchRow(id: UUID(), toolID: defaultTool, directory: Self.defaultDirectory(), count: 0)]
        }

        var remaining = clampedTotal

        for index in launchRows.indices {
            let assigned = min(24, remaining)
            launchRows[index].count = assigned
            remaining -= assigned
        }

        while remaining > 0 {
            let defaultTool = tools.first?.id ?? "claude"
            let assigned = min(24, remaining)
            launchRows.append(LaunchRow(id: UUID(), toolID: defaultTool, directory: Self.defaultDirectory(), count: assigned))
            remaining -= assigned
        }
    }

    func toggleScreen(_ screenID: String) {
        if selectedScreenIDs.contains(screenID) {
            if selectedScreenIDs.count > 1 {
                selectedScreenIDs.remove(screenID)
            }
        } else {
            selectedScreenIDs.insert(screenID)
        }
    }

    func setSelectedScreens(_ screenIDs: Set<String>) {
        let availableIDs = Set(availableScreens.map(\.id))
        var filtered = screenIDs.filter { availableIDs.contains($0) }

        if filtered.isEmpty {
            if let preferred = ScreenGeometry.preferredDisplayID(), availableIDs.contains(preferred) {
                filtered = [preferred]
            } else if let first = availableScreens.first?.id {
                filtered = [first]
            }
        }

        selectedScreenIDs = filtered
    }

    func isScreenSelected(_ screenID: String) -> Bool {
        selectedScreenIDs.contains(screenID)
    }

    func removeRow(_ rowID: UUID) {
        launchRows.removeAll(where: { $0.id == rowID })
        if launchRows.isEmpty {
            addTerminal()
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

    func attachExistingWindows() {
        let existingSession = store.loadActiveSession()
        let excludedIDs = Set(existingSession?.windowIDs ?? [])

        do {
            let imported = try launchService.importExistingWindows(for: selectedTerminal, excluding: excludedIDs)
            guard !imported.isEmpty else {
                setStatus("No additional \(selectedTerminal.label) windows found.", level: .info)
                return
            }

            var session: ActiveSession
            if let existingSession, existingSession.request.terminal == selectedTerminal {
                session = existingSession
                session.agentWindows.append(contentsOf: imported)
            } else {
                let request = currentRequest()
                session = ActiveSession(agentWindows: imported, request: request)
            }

            var seenWindowIDs: Set<Int> = []
            session.agentWindows = session.agentWindows.filter { seenWindowIDs.insert($0.windowID).inserted }
            store.saveActiveSession(session)
            setStatus("Attached \(imported.count) existing \(selectedTerminal.label) windows.", level: .success)
        } catch {
            setStatus(error.localizedDescription, level: .error)
        }
    }

    private func launch(request: LaunchRequest) {
        let screens = resolvedScreens(for: request)
        guard !screens.isEmpty else {
            setStatus("Unable to read selected display geometry.", level: .error)
            return
        }

        do {
            let session = try launchService.launch(request: request, screens: screens)
            store.saveActiveSession(session)
            store.saveLastLaunch(request)
            setStatus("Launched \(request.summary(using: tools)) via \(request.terminal.label).", level: .success)
        } catch {
            setStatus(error.localizedDescription, level: .error)
        }
    }

    private func apply(request: LaunchRequest) {
        refreshDisplays(preferredIDs: request.screenIDs)
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
            launchItems: items,
            screenIDs: orderedSelectedScreenIDs()
        )
    }

    private func orderedSelectedScreenIDs() -> [String] {
        availableScreens.map(\.id).filter { selectedScreenIDs.contains($0) }
    }

    private func resolvedScreens(for request: LaunchRequest) -> [ScreenGeometry] {
        refreshDisplays(preferredIDs: request.screenIDs)
        let ids = orderedSelectedScreenIDs()
        if ids.isEmpty {
            return availableScreens.map(\.geometry)
        }

        let selected = availableScreens.filter { ids.contains($0.id) }
        return selected.map(\.geometry)
    }

    private func refreshDisplays(preferredIDs: [String]) {
        availableScreens = ScreenGeometry.allDisplays()
        let availableIDs = Set(availableScreens.map(\.id))

        if preferredIDs.isEmpty {
            selectedScreenIDs = selectedScreenIDs.filter { availableIDs.contains($0) }
        } else {
            selectedScreenIDs = Set(preferredIDs).filter { availableIDs.contains($0) }
        }

        if selectedScreenIDs.isEmpty {
            if let preferred = ScreenGeometry.preferredDisplayID(), availableIDs.contains(preferred) {
                selectedScreenIDs = [preferred]
            } else if let firstID = availableScreens.first?.id {
                selectedScreenIDs = [firstID]
            }
        }
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
