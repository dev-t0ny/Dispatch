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
        var agents: [AgentWindow] = []

        for plan in plans {
            let launchCommand = makeLaunchCommand(directory: plan.directory, toolCommand: plan.tool.command)
            let windowID = try controller.launchWindow(command: launchCommand)

            let agent = AgentWindow(
                id: UUID(),
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

            try controller.applyIdentity(windowID: agent.windowID, title: agent.title, badge: agent.badge, tone: agent.tone)
            agents.append(agent)
            usleep(80_000)
        }

        let targetBounds = tiler.bounds(for: agents.count, layout: request.layout, screens: screens)
        for (agent, bounds) in zip(agents, targetBounds) {
            try controller.setBounds(windowID: agent.windowID, bounds: bounds)
        }

        return ActiveSession(agentWindows: agents, request: request)
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

        let existing = try controller.listWindowIDs().filter { !windowIDs.contains($0) }
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

    private func makeLaunchCommand(directory: String, toolCommand: String) -> String {
        let shellBody = "cd \(Shell.singleQuote(directory)) && exec \(toolCommand)"
        return "zsh -lc \(Shell.singleQuote(shellBody))"
    }
}
