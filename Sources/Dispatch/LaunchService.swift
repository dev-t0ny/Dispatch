import AppKit
import Foundation

final class LaunchService {
    private let tools: [ToolDefinition]
    private let controllers: [TerminalApp: any TerminalControlling]
    private let tiler: WindowTiler

    init(
        tools: [ToolDefinition] = ToolDefinition.default,
        controllers: [TerminalApp: any TerminalControlling] = [
            .iTerm2: ITermController(),
            .terminal: TerminalController()
        ],
        tiler: WindowTiler = WindowTiler()
    ) {
        self.tools = tools
        self.controllers = controllers
        self.tiler = tiler
    }

    func toolList() -> [ToolDefinition] {
        tools
    }

    func launch(request: LaunchRequest, screens: [ScreenGeometry]) throws -> ActiveSession {
        guard request.totalCount > 0 else {
            throw DispatchError.validation("Pick at least one tool instance.")
        }

        guard let controller = controllers[request.terminal] else {
            throw DispatchError.system("No launcher configured for \(request.terminal.label).")
        }

        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: request.terminal.bundleIdentifier) != nil else {
            throw DispatchError.system("\(request.terminal.label) is not installed.")
        }

        let plans = try validatedLaunchPlans(from: request.launchItems)
        let sessionID = UUID().uuidString
        let wrapperPath = resolveDispatchAgentPath()
        var agents: [AgentWindow] = []

        for plan in plans {
            let agentID = UUID()
            let launchCommand = try makeLaunchCommand(
                directory: plan.directory,
                toolID: plan.tool.id,
                toolCommand: plan.tool.command,
                sessionID: sessionID,
                agentID: agentID.uuidString,
                wrapperPath: wrapperPath
            )
            let windowID = try controller.launchWindow(command: launchCommand)

            let agent = AgentWindow(
                id: agentID,
                windowID: windowID,
                toolID: plan.tool.id,
                directory: plan.directory,
                name: plan.name,
                role: plan.role,
                objective: plan.objective,
                tone: plan.tone,
                slot: plan.slot,
                launchedAt: Date(),
                state: .running,
                lastFocusedAt: nil
            )

            do {
                try controller.applyIdentity(windowID: agent.windowID, title: agent.title, badge: agent.badge, tone: agent.tone)
            } catch {
                // Identity decoration should never block terminal launch.
            }
            agents.append(agent)
            usleep(80_000)
        }

        let targetBounds = tiler.bounds(for: agents.count, layout: request.layout, screens: screens)
        for (agent, bounds) in zip(agents, targetBounds) {
            try controller.setBounds(windowID: agent.windowID, bounds: bounds)
        }

        return ActiveSession(sessionID: sessionID, agentWindows: agents, request: request)
    }

    func close(session: ActiveSession) throws {
        guard let controller = controllers[session.request.terminal] else {
            throw DispatchError.system("No launcher configured for \(session.request.terminal.label).")
        }

        for agent in session.agentWindows {
            try controller.closeWindow(windowID: agent.windowID)
        }
    }

    func focus(windowID: Int, terminal: TerminalApp) throws {
        guard let controller = controllers[terminal] else {
            throw DispatchError.system("No launcher configured for \(terminal.label).")
        }
        try controller.focusWindow(windowID: windowID)
    }

    func applyIdentity(agent: AgentWindow, terminal: TerminalApp) throws {
        guard let controller = controllers[terminal] else {
            throw DispatchError.system("No launcher configured for \(terminal.label).")
        }
        try controller.applyIdentity(windowID: agent.windowID, title: agent.title, badge: agent.badge, tone: agent.tone)
    }

    func importExistingWindows(for terminal: TerminalApp, excluding windowIDs: Set<Int>) throws -> [AgentWindow] {
        guard let controller = controllers[terminal] else {
            throw DispatchError.system("No launcher configured for \(terminal.label).")
        }

        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleIdentifier) != nil else {
            throw DispatchError.system("\(terminal.label) is not installed.")
        }

        let snapshots: [TerminalWindowSnapshot]
        do {
            snapshots = try controller.listWindowSnapshots()
        } catch {
            return []
        }

        let existing = snapshots.map(\.windowID).filter { !windowIDs.contains($0) }
        let now = Date()
        return existing.enumerated().map { index, windowID in
            AgentWindow(
                id: UUID(),
                windowID: windowID,
                toolID: "external",
                directory: "",
                name: "External \(terminal.label) \(index + 1)",
                role: "Attached",
                objective: "Manual terminal",
                tone: .slate,
                slot: nil,
                launchedAt: now,
                state: .running,
                lastFocusedAt: nil
            )
        }
    }

    func listWindowSnapshots(for terminal: TerminalApp) throws -> [TerminalWindowSnapshot] {
        guard let controller = controllers[terminal] else {
            throw DispatchError.system("No launcher configured for \(terminal.label).")
        }

        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleIdentifier) != nil else {
            return []
        }

        do {
            return try controller.listWindowSnapshots()
        } catch {
            return []
        }
    }

    private struct LaunchPlan {
        let tool: ToolDefinition
        let directory: String
        let name: String
        let role: String
        let objective: String
        let tone: AgentTone
        let slot: Int?
    }

    private func validatedLaunchPlans(from items: [LaunchItem]) throws -> [LaunchPlan] {
        var plans: [LaunchPlan] = []

        for item in items where item.count > 0 {
            guard let tool = tools.first(where: { $0.id == item.toolID }) else {
                throw DispatchError.validation("Unknown tool selected: \(item.toolID)")
            }

            let expandedDirectory = (item.directory as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expandedDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw DispatchError.validation("Directory does not exist: \(item.directory)")
            }

            let executable = Shell.executableName(from: tool.command)
            guard Shell.isExecutableAvailable(executable) else {
                throw DispatchError.validation("Tool '\(executable)' is not in PATH.")
            }

            for instance in 0..<item.count {
                let indexedName = item.count > 1 ? "\(item.agentName) \(instance + 1)" : item.agentName
                let slot = item.startSlot.map { $0 + instance }
                plans.append(
                    LaunchPlan(
                        tool: tool,
                        directory: expandedDirectory,
                        name: indexedName,
                        role: item.role,
                        objective: item.objective,
                        tone: item.tone,
                        slot: slot
                    )
                )
            }
        }

        if plans.isEmpty {
            throw DispatchError.validation("Pick at least one tool instance.")
        }

        return plans
    }

    private func makeLaunchCommand(
        directory: String,
        toolID: String,
        toolCommand: String,
        sessionID: String,
        agentID: String,
        wrapperPath: String?
    ) throws -> String {
        let scriptPath = try writeLaunchScript(
            directory: directory,
            toolID: toolID,
            toolCommand: toolCommand,
            sessionID: sessionID,
            agentID: agentID,
            wrapperPath: wrapperPath
        )

        return "/bin/zsh \(Shell.singleQuote(scriptPath))"
    }

    private func writeLaunchScript(
        directory: String,
        toolID: String,
        toolCommand: String,
        sessionID: String,
        agentID: String,
        wrapperPath: String?
    ) throws -> String {
        let scriptID = UUID().uuidString
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dispatch-launch-\(scriptID).sh", isDirectory: false)

        let commandB64 = Data(toolCommand.utf8).base64EncodedString()
        let exportLine = "export DISPATCH_SESSION_ID=\(Shell.singleQuote(sessionID)) DISPATCH_AGENT_ID=\(Shell.singleQuote(agentID)) DISPATCH_TOOL=\(Shell.singleQuote(toolID)) DISPATCH_TOOL_COMMAND_B64=\(Shell.singleQuote(commandB64))"

        let commandLine: String
        if let wrapperPath {
            let escapedWrapper = Shell.singleQuote(wrapperPath)
            commandLine = "\(escapedWrapper) --tool \(Shell.singleQuote(toolID)) --session-id \(Shell.singleQuote(sessionID)) --agent-id \(Shell.singleQuote(agentID))"
        } else {
            commandLine = toolCommand
        }

        let script = """
        #!/bin/zsh
        set +e
        cd \(Shell.singleQuote(directory))
        \(exportLine)
        \(commandLine)
        dispatch_exit_code=$?
        if [[ $dispatch_exit_code -ne 0 ]]; then
          print "[Dispatch] Command exited with code $dispatch_exit_code"
        fi
        exec /bin/zsh -l
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL.path
    }

    private func resolveDispatchAgentPath() -> String? {
        if let bundled = Bundle.main.path(forAuxiliaryExecutable: "dispatch-agent"), FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }

        let executablePath = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("dispatch-agent").path
        if FileManager.default.isExecutableFile(atPath: executablePath) {
            return executablePath
        }

        return Shell.executablePath("dispatch-agent")
    }
}
