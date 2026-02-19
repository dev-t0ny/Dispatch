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
    @Published var activeAgents: [AgentWindow]
    @Published var liveWindowSnapshots: [TerminalWindowSnapshot]

    let tools: [ToolDefinition]

    private let launchService: LaunchService
    private let store: SessionStore
    private let overlayController = AttentionOverlayController()
    private var lastRuntimeSyncError: String?
    private var eventLogByteOffset: UInt64

    init(launchService: LaunchService = LaunchService(), store: SessionStore = SessionStore()) {
        self.launchService = launchService
        self.store = store
        tools = launchService.toolList()
        presets = store.loadPresets().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        availableScreens = ScreenGeometry.allDisplays()
        selectedScreenIDs = []
        activeAgents = []
        liveWindowSnapshots = []
        lastRuntimeSyncError = nil
        eventLogByteOffset = 0

        let defaultDirectory = Self.defaultDirectory()
        let defaultTool = tools.first?.id ?? "claude"
        launchRows = [LaunchRow(id: UUID(), toolID: defaultTool, directory: defaultDirectory, count: 6)]

        refreshDisplays(preferredIDs: [])

        if let last = store.loadLastLaunch() {
            apply(request: last)
        }

        refreshActiveAgents()
        primeEventCursor()
        refreshRuntimeContext(silent: true)
    }

    var totalInstances: Int {
        launchRows.map(\.count).reduce(0, +)
    }

    var needsAttentionAgents: [AgentWindow] {
        activeAgents.filter { $0.state == .needsInput || $0.state == .blocked }
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
            overlayController.hideAll()
            refreshActiveAgents()
            setStatus("Closed \(activeSession.windowIDs.count) Dispatch windows.", level: .success)
        } catch {
            setStatus(error.localizedDescription, level: .error)
        }
    }

    func attachExistingWindows() {
        refreshRuntimeContext(silent: false)
    }

    func refreshRuntimeContext(silent: Bool = true) {
        applyPendingRuntimeEvents()
        refreshDisplays(preferredIDs: [])

        do {
            let snapshots = try launchService.listWindowSnapshots(for: selectedTerminal)
            liveWindowSnapshots = snapshots
            try autoAttachSnapshots(snapshots: snapshots, silent: silent)
            lastRuntimeSyncError = nil
        } catch {
            liveWindowSnapshots = []
            let message = error.localizedDescription
            if !silent || message != lastRuntimeSyncError {
                setStatus(message, level: .error)
            }
            lastRuntimeSyncError = message
        }

        scanForPrompts()
        syncOverlays()
    }

    func focusAgent(_ agentID: UUID) {
        guard var session = store.loadActiveSession() else {
            setStatus("No active session to focus.", level: .info)
            return
        }

        guard let index = session.agentWindows.firstIndex(where: { $0.id == agentID }) else {
            setStatus("Agent no longer exists in session.", level: .error)
            return
        }

        do {
            let terminal = session.request.terminal
            let agent = session.agentWindows[index]
            try launchService.focus(windowID: agent.windowID, terminal: terminal)

            session.agentWindows[index].lastFocusedAt = Date()
            session.focusHistory.append(agent.id)
            store.saveActiveSession(session)
            refreshActiveAgents()
        } catch {
            setStatus(error.localizedDescription, level: .error)
        }
    }

    func setAgentState(_ state: AgentState, for agentID: UUID) {
        guard var session = store.loadActiveSession() else { return }
        guard let index = session.agentWindows.firstIndex(where: { $0.id == agentID }) else { return }

        session.agentWindows[index].state = state
        let terminal = session.request.terminal

        do {
            try launchService.applyIdentity(agent: session.agentWindows[index], terminal: terminal)
        } catch {
            setStatus(error.localizedDescription, level: .error)
        }

        store.saveActiveSession(session)
        refreshActiveAgents()

        // Immediately sync overlays so the overlay appears/disappears on manual state change.
        syncOverlays()
    }

    func focusNextAttention() {
        let queue = needsAttentionAgents
        guard !queue.isEmpty else {
            setStatus("No terminals currently need attention.", level: .info)
            return
        }

        let sorted = queue.sorted { lhs, rhs in
            if lhs.state != rhs.state {
                return lhs.state == .needsInput
            }
            let leftDate = lhs.lastFocusedAt ?? lhs.launchedAt
            let rightDate = rhs.lastFocusedAt ?? rhs.launchedAt
            return leftDate < rightDate
        }

        if let target = sorted.first {
            focusAgent(target.id)
        }
    }

    private func launch(request: LaunchRequest) {
        let screens = resolvedScreens(for: request)
        guard !screens.isEmpty else {
            setStatus("Unable to read selected display geometry.", level: .error)
            return
        }

        setStatus("Launching...", level: .info)

        // Dispatch to a background task so blocking Process calls (which,
        // isExecutableAvailable, executablePath) don't freeze the UI.
        let service = launchService
        let toolsList = tools
        Task.detached { [store] in
            do {
                let session = try service.launch(request: request, screens: screens)
                await MainActor.run {
                    store.saveActiveSession(session)
                    store.saveLastLaunch(request)
                    self.refreshActiveAgents()
                    self.refreshRuntimeContext(silent: true)
                    self.setStatus("Launched \(request.summary(using: toolsList)) via \(request.terminal.label).", level: .success)
                }
            } catch {
                await MainActor.run {
                    self.setStatus(error.localizedDescription, level: .error)
                }
            }
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
            screenIDs: []
        )
    }

    private func resolvedScreens(for request: LaunchRequest) -> [ScreenGeometry] {
        refreshDisplays(preferredIDs: request.screenIDs)
        return availableScreens.map(\.geometry)
    }

    private func refreshDisplays(preferredIDs: [String]) {
        availableScreens = ScreenGeometry.allDisplays()
        selectedScreenIDs = Set(availableScreens.map(\.id))
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

    private func refreshActiveAgents() {
        let session = store.loadActiveSession()
        activeAgents = session?.agentWindows ?? []
    }

    private func primeEventCursor() {
        // Skip to current end-of-file so we only process events written after launch.
        eventLogByteOffset = DispatchEventLog.fileSize()
    }

    private func applyPendingRuntimeEvents() {
        let (freshLines, newOffset) = DispatchEventLog.readNewLines(fromByteOffset: eventLogByteOffset)
        eventLogByteOffset = newOffset

        guard !freshLines.isEmpty else { return }
        guard var session = store.loadActiveSession() else { return }

        var didChange = false
        let decoder = JSONDecoder()

        for line in freshLines {
            guard let data = line.data(using: .utf8) else { continue }
            guard let event = try? decoder.decode(DispatchRuntimeEvent.self, from: data) else { continue }
            guard event.sessionID == session.sessionID else { continue }
            guard let agentUUID = UUID(uuidString: event.agentID) else { continue }
            guard let index = session.agentWindows.firstIndex(where: { $0.id == agentUUID }) else { continue }

            if let mappedState = mappedAgentState(from: event.state), session.agentWindows[index].state != mappedState {
                session.agentWindows[index].state = mappedState
                didChange = true
                if mappedState == .needsInput || mappedState == .blocked {
                    let reason = event.reason ?? "Action needed"
                    setStatus("\(session.agentWindows[index].name): \(reason)", level: .info)
                }
            }
        }

        if didChange {
            store.saveActiveSession(session)
            refreshActiveAgents()
        }
    }

    private func mappedAgentState(from runtimeState: String) -> AgentState? {
        switch runtimeState {
        case "running":
            return .running
        case "needs_input":
            return .needsInput
        case "blocked", "error":
            return .blocked
        case "done":
            return .done
        default:
            return nil
        }
    }

    /// Scan running agents via TTY process monitoring and auto-transition to needsInput
    /// when the tool appears idle, or back to running when it resumes work.
    private func scanForPrompts() {
        guard var session = store.loadActiveSession() else { return }
        let terminal = session.request.terminal

        let idleAgentIDs = launchService.detectIdleAgents(
            agents: session.agentWindows,
            terminal: terminal
        )

        var didChange = false

        for index in session.agentWindows.indices {
            let agent = session.agentWindows[index]
            let isIdle = idleAgentIDs.contains(agent.id)

            if isIdle && agent.state == .running {
                // Tool is idle → needs input.
                session.agentWindows[index].state = .needsInput
                didChange = true
            } else if !isIdle && agent.state == .needsInput {
                // Tool resumed work → back to running (auto-dismiss).
                session.agentWindows[index].state = .running
                didChange = true
            }
        }

        if didChange {
            store.saveActiveSession(session)
            refreshActiveAgents()
        }
    }

    /// Show or hide transparent overlays based on current agent states and bounds.
    private func syncOverlays() {
        let session = store.loadActiveSession()
        guard let session else {
            overlayController.hideAll()
            return
        }

        let snapshotMap = Dictionary(
            uniqueKeysWithValues: liveWindowSnapshots.map { ($0.windowID, $0) }
        )

        // Track which agents should have overlays.
        var activeOverlayIDs: Set<UUID> = []

        for agent in session.agentWindows {
            let shouldOverlay = agent.state == .needsInput || agent.state == .blocked

            if shouldOverlay, let snapshot = snapshotMap[agent.windowID] {
                let bounds = WindowBounds(
                    left: snapshot.left,
                    top: snapshot.top,
                    right: snapshot.right,
                    bottom: snapshot.bottom
                )
                overlayController.showOverlay(for: agent.id, bounds: bounds, state: agent.state)
                activeOverlayIDs.insert(agent.id)
            } else {
                overlayController.hideOverlay(for: agent.id)
            }
        }

        // Hide overlays for agents that no longer exist.
        let allAgentIDs = Set(session.agentWindows.map(\.id))
        for agent in session.agentWindows where !activeOverlayIDs.contains(agent.id) {
            overlayController.hideOverlay(for: agent.id)
        }
        _ = allAgentIDs  // suppress unused warning
    }

    private func autoAttachSnapshots(snapshots: [TerminalWindowSnapshot], silent: Bool) throws {
        let openIDs = Set(snapshots.map(\.windowID))
        let session = store.loadActiveSession()

        // Case 1: Active session matches the selected terminal — reconcile windows.
        if var existing = session, existing.request.terminal == selectedTerminal {
            existing.agentWindows.removeAll(where: { !openIDs.contains($0.windowID) })

            let knownIDs = Set(existing.agentWindows.map(\.windowID))
            let imported = try launchService.importExistingWindows(for: selectedTerminal, excluding: knownIDs)
            if !imported.isEmpty {
                existing.agentWindows.append(contentsOf: imported)
                if !silent {
                    setStatus("Detected \(imported.count) additional \(selectedTerminal.label) windows.", level: .success)
                }
            }

            if existing.agentWindows.isEmpty {
                store.saveActiveSession(nil)
            } else {
                store.saveActiveSession(existing)
            }
            refreshActiveAgents()
            return
        }

        // Case 2: Active session exists for a *different* terminal. Show
        // detected windows for the selected terminal in the UI without
        // overwriting the persisted session (which preserves agent IDs,
        // state tracking, and event log correlation for the real launch).
        if session != nil, session?.request.terminal != selectedTerminal {
            let imported = try launchService.importExistingWindows(for: selectedTerminal, excluding: [])
            // Show these in the UI only — do NOT call store.saveActiveSession.
            activeAgents = imported
            if !silent && !imported.isEmpty {
                setStatus("Showing \(imported.count) detected \(selectedTerminal.label) windows. Switch back to \(session!.request.terminal.label) to manage your launched session.", level: .info)
            }
            return
        }

        // Case 3: No active session at all — auto-import what we find.
        let imported = try launchService.importExistingWindows(for: selectedTerminal, excluding: [])
        guard !imported.isEmpty else {
            refreshActiveAgents()
            return
        }

        let request = LaunchRequest(terminal: selectedTerminal, layout: layout, launchItems: [], screenIDs: [])
        store.saveActiveSession(ActiveSession(agentWindows: imported, request: request))
        refreshActiveAgents()

        if !silent {
            setStatus("Detected \(imported.count) existing \(selectedTerminal.label) windows.", level: .success)
        }
    }
}
