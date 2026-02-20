import AppKit
import Foundation
import SwiftUI

struct LaunchRow: Identifiable, Hashable {
    let id: UUID
    var toolID: String
    var directory: String
    var count: Int
}

struct LaunchProgress {
    let launched: Int
    let total: Int
}

/// Results gathered on a background thread for `refreshRuntimeContext`.
private struct RuntimeSnapshot: Sendable {
    let freshLines: [String]
    let newByteOffset: UInt64
    let snapshots: [TerminalWindowSnapshot]?
    let snapshotError: String?
    let idleAgentIDs: Set<UUID>
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
    @Published var launchProgress: LaunchProgress?
    @Published var showCloseConfirmation = false

    let tools: [ToolDefinition]

    private let launchService: LaunchService
    private let store: SessionStore
    private let overlayController = AttentionOverlayController()
    private var lastRuntimeSyncError: String?
    private var eventLogByteOffset: UInt64
    /// Guards against overlapping background refresh cycles.
    private var isRefreshing = false
    /// The currently running launch task (for cancellation support).
    private var launchTask: Task<Void, Never>?
    /// Auto-dismiss timer for status messages.
    private var statusDismissTask: Task<Void, Never>?

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
        Task { await refreshRuntimeContext(silent: true) }
    }

    var totalInstances: Int {
        launchRows.map(\.count).reduce(0, +)
    }

    var needsAttentionAgents: [AgentWindow] {
        activeAgents.filter { $0.state == .needsInput || $0.state == .blocked }
    }

    func addTerminal() {
        let defaultTool = tools.first?.id ?? "claude"
        let currentTotal = totalInstances
        launchRows.append(LaunchRow(id: UUID(), toolID: defaultTool, directory: Self.defaultDirectory(), count: 0))
        distributeCount(currentTotal)
    }

    func setTotalInstances(_ total: Int) {
        let clampedTotal = max(0, min(240, total))

        if launchRows.isEmpty {
            let defaultTool = tools.first?.id ?? "claude"
            launchRows = [LaunchRow(id: UUID(), toolID: defaultTool, directory: Self.defaultDirectory(), count: 0)]
        }

        distributeCount(clampedTotal)
    }

    /// Distribute the total window count evenly across all launch rows.
    private func distributeCount(_ total: Int) {
        guard !launchRows.isEmpty else { return }
        let perRow = total / launchRows.count
        let remainder = total % launchRows.count

        for index in launchRows.indices {
            launchRows[index].count = perRow + (index < remainder ? 1 : 0)
        }
    }

    func removeRow(_ rowID: UUID) {
        let currentTotal = totalInstances
        launchRows.removeAll(where: { $0.id == rowID })
        if launchRows.isEmpty {
            let defaultTool = tools.first?.id ?? "claude"
            launchRows = [LaunchRow(id: UUID(), toolID: defaultTool, directory: Self.defaultDirectory(), count: 0)]
        }
        distributeCount(currentTotal)
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
        Task { await refreshRuntimeContext(silent: false) }
    }

    func refreshRuntimeContext(silent: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Capture values needed by the background closure.
        let terminal = selectedTerminal
        let byteOffset = eventLogByteOffset
        let service = launchService
        let session = store.loadActiveSession()

        // --- Heavy work on a background thread ---
        let snapshot: RuntimeSnapshot = await Task.detached {
            // 1. Read new event log lines (file I/O).
            let (freshLines, newOffset) = DispatchEventLog.readNewLines(fromByteOffset: byteOffset)

            // 2. List terminal window snapshots (AppleScript IPC).
            var snapshotResult: [TerminalWindowSnapshot]?
            var snapshotError: String?
            do {
                snapshotResult = try service.listWindowSnapshots(for: terminal)
            } catch {
                snapshotError = error.localizedDescription
            }

            // 3. Detect idle agents (AppleScript + ps subprocess).
            var idleAgentIDs: Set<UUID> = []
            if let session {
                idleAgentIDs = service.detectIdleAgents(
                    agents: session.agentWindows,
                    terminal: session.request.terminal
                )
            }

            return RuntimeSnapshot(
                freshLines: freshLines,
                newByteOffset: newOffset,
                snapshots: snapshotResult,
                snapshotError: snapshotError,
                idleAgentIDs: idleAgentIDs
            )
        }.value

        // --- Apply results on the main thread using a single cached session ---
        var cachedSession = store.loadActiveSession()

        applyPendingRuntimeEvents(session: &cachedSession, freshLines: snapshot.freshLines, newByteOffset: snapshot.newByteOffset)
        refreshDisplays(preferredIDs: [])

        if let snapshots = snapshot.snapshots {
            liveWindowSnapshots = snapshots
            reconcileSessionWindows(session: &cachedSession, snapshots: snapshots)
            if snapshot.snapshotError == nil {
                lastRuntimeSyncError = nil
            }
        } else {
            liveWindowSnapshots = []
            if let message = snapshot.snapshotError {
                if !silent || message != lastRuntimeSyncError {
                    setStatus(message, level: .error)
                }
                lastRuntimeSyncError = message
            }
        }

        scanForPrompts(session: &cachedSession, idleAgentIDs: snapshot.idleAgentIDs)
        syncOverlays(session: cachedSession)
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
            // Cap history to prevent unbounded growth in JSON serialization.
            if session.focusHistory.count > 100 {
                session.focusHistory = Array(session.focusHistory.suffix(100))
            }
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
        launchTask = Task.detached { [store] in
            do {
                let session = try await service.launch(request: request, screens: screens) { launched, total in
                    Task { @MainActor in
                        self.launchProgress = LaunchProgress(launched: launched, total: total)
                    }
                }
                await MainActor.run {
                    self.launchProgress = nil
                    store.saveActiveSession(session)
                    store.saveLastLaunch(request)
                    self.refreshActiveAgents()
                    self.setStatus("Launched \(request.summary(using: toolsList)) via \(request.terminal.label).", level: .success)
                }
                await self.refreshRuntimeContext(silent: true)
            } catch is CancellationError {
                await MainActor.run {
                    self.launchProgress = nil
                    self.setStatus("Launch cancelled.", level: .info)
                }
            } catch {
                await MainActor.run {
                    self.launchProgress = nil
                    self.setStatus(error.localizedDescription, level: .error)
                }
            }
        }
    }

    func cancelLaunch() {
        launchTask?.cancel()
        launchTask = nil
        launchProgress = nil
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
            screenIDs: Array(selectedScreenIDs)
        )
    }

    private func resolvedScreens(for request: LaunchRequest) -> [ScreenGeometry] {
        refreshDisplays(preferredIDs: request.screenIDs)
        let selected = availableScreens.filter { selectedScreenIDs.contains($0.id) }
        return selected.isEmpty ? availableScreens.map(\.geometry) : selected.map(\.geometry)
    }

    func toggleScreen(_ screenID: String) {
        if selectedScreenIDs.contains(screenID) {
            // Don't allow deselecting the last screen.
            if selectedScreenIDs.count > 1 {
                selectedScreenIDs.remove(screenID)
            }
        } else {
            selectedScreenIDs.insert(screenID)
        }
    }

    private func refreshDisplays(preferredIDs: [String]) {
        let newScreens = ScreenGeometry.allDisplays()
        let newIDs = Set(newScreens.map(\.id))
        availableScreens = newScreens

        if !preferredIDs.isEmpty {
            // Restore from saved preset/request.
            selectedScreenIDs = Set(preferredIDs).intersection(newIDs)
        }

        // If no valid selection exists (first launch, or all selected screens
        // were disconnected), default to all screens.
        if selectedScreenIDs.isEmpty || !selectedScreenIDs.isSubset(of: newIDs) {
            selectedScreenIDs = newIDs
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
        withAnimation(.easeInOut(duration: 0.15)) {
            status = StatusMessage(text: text, level: level)
        }

        // Auto-dismiss after a delay based on severity.
        statusDismissTask?.cancel()
        let seconds: UInt64 = switch level {
            case .success: 3
            case .info: 4
            case .error: 6
        }
        statusDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self?.status = nil
            }
        }
    }

    private func refreshActiveAgents() {
        let session = store.loadActiveSession()
        let newAgents = session?.agentWindows ?? []
        // Animate only when the agent list or states actually change.
        if newAgents.map(\.id) != activeAgents.map(\.id) || newAgents.map(\.state) != activeAgents.map(\.state) {
            withAnimation(.easeInOut(duration: 0.2)) {
                activeAgents = newAgents
            }
        } else {
            activeAgents = newAgents
        }
    }

    private func primeEventCursor() {
        // Skip to current end-of-file so we only process events written after launch.
        eventLogByteOffset = DispatchEventLog.fileSize()
    }

    private func applyPendingRuntimeEvents(session: inout ActiveSession?, freshLines: [String], newByteOffset: UInt64) {
        eventLogByteOffset = newByteOffset

        guard !freshLines.isEmpty else { return }
        guard var currentSession = session else { return }

        var didChange = false
        let decoder = JSONDecoder()

        for line in freshLines {
            guard let data = line.data(using: .utf8) else { continue }
            guard let event = try? decoder.decode(DispatchRuntimeEvent.self, from: data) else { continue }
            guard event.sessionID == currentSession.sessionID else { continue }
            guard let agentUUID = UUID(uuidString: event.agentID) else { continue }
            guard let index = currentSession.agentWindows.firstIndex(where: { $0.id == agentUUID }) else { continue }

            if let mappedState = mappedAgentState(from: event.state), currentSession.agentWindows[index].state != mappedState {
                currentSession.agentWindows[index].state = mappedState
                didChange = true
                if mappedState == .needsInput || mappedState == .blocked {
                    let reason = event.reason ?? "Action needed"
                    setStatus("\(currentSession.agentWindows[index].name): \(reason)", level: .info)
                }
            }
        }

        if didChange {
            session = currentSession
            store.saveActiveSession(currentSession)
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

    /// Apply pre-computed idle detection results to agent states.
    private func scanForPrompts(session: inout ActiveSession?, idleAgentIDs: Set<UUID>) {
        guard var currentSession = session else { return }

        var didChange = false

        for index in currentSession.agentWindows.indices {
            let agent = currentSession.agentWindows[index]
            let isIdle = idleAgentIDs.contains(agent.id)

            if isIdle && agent.state == .running {
                // Tool is idle -> needs input.
                currentSession.agentWindows[index].state = .needsInput
                didChange = true
            } else if !isIdle && agent.state == .needsInput {
                // Tool resumed work -> back to running (auto-dismiss).
                currentSession.agentWindows[index].state = .running
                didChange = true
            }
        }

        if didChange {
            session = currentSession
            store.saveActiveSession(currentSession)
            refreshActiveAgents()
        }
    }

    /// Show or hide border overlays based on current agent states and window bounds.
    private func syncOverlays(session: ActiveSession? = nil) {
        let resolvedSession = session ?? store.loadActiveSession()
        guard let resolvedSession else {
            overlayController.hideAll()
            return
        }

        // Tell the overlay controller which terminal app to track via CG.
        overlayController.terminalAppName = selectedTerminal.cgOwnerName

        let snapshotMap = Dictionary(
            uniqueKeysWithValues: liveWindowSnapshots.map { ($0.windowID, $0) }
        )

        for agent in resolvedSession.agentWindows {
            let shouldOverlay = agent.state == .needsInput || agent.state == .blocked

            if shouldOverlay, let snapshot = snapshotMap[agent.windowID] {
                let bounds = WindowBounds(
                    left: snapshot.left,
                    top: snapshot.top,
                    right: snapshot.right,
                    bottom: snapshot.bottom
                )
                overlayController.showOverlay(for: agent.id, windowID: agent.windowID, bounds: bounds, state: agent.state)
            } else {
                overlayController.hideOverlay(for: agent.id)
            }
        }
    }

    /// Reconcile the active session with the current terminal window list.
    /// Removes agents whose windows have been closed. Does NOT auto-import
    /// external windows — only windows launched by Dispatch are tracked.
    private func reconcileSessionWindows(session: inout ActiveSession?, snapshots: [TerminalWindowSnapshot]) {
        guard var existing = session, existing.request.terminal == selectedTerminal else {
            refreshActiveAgents()
            return
        }

        let openIDs = Set(snapshots.map(\.windowID))
        existing.agentWindows.removeAll(where: { !openIDs.contains($0.windowID) })

        if existing.agentWindows.isEmpty {
            session = nil
            store.saveActiveSession(nil)
        } else {
            session = existing
            store.saveActiveSession(existing)
        }
        refreshActiveAgents()
    }
}
