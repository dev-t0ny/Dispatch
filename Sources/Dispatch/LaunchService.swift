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

    func launch(request: LaunchRequest, screen: ScreenGeometry) throws -> ActiveSession {
        guard request.totalCount > 0 else {
            throw DispatchError.validation("Pick at least one tool instance.")
        }

        guard let controller = controllers[request.terminal] else {
            throw DispatchError.system("No launcher configured for \(request.terminal.label).")
        }

        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: request.terminal.bundleIdentifier) != nil else {
            throw DispatchError.system("\(request.terminal.label) is not installed.")
        }

        let validLaunchItems = try validatedLaunchItems(from: request.launchItems)

        var windowIDs: [Int] = []

        for item in validLaunchItems {
            let launchCommand = makeLaunchCommand(directory: item.directory, toolCommand: item.tool.command)
            let count = item.count
            for _ in 0..<count {
                let windowID = try controller.launchWindow(command: launchCommand)
                windowIDs.append(windowID)
                usleep(90_000)
            }
        }

        let targetBounds = tiler.bounds(for: request.totalCount, layout: request.layout, screen: screen)
        for (windowID, bounds) in zip(windowIDs, targetBounds) {
            try controller.setBounds(windowID: windowID, bounds: bounds)
        }

        return ActiveSession(windowIDs: windowIDs, request: request, launchedAt: Date())
    }

    func close(session: ActiveSession) throws {
        guard let controller = controllers[session.request.terminal] else {
            throw DispatchError.system("No launcher configured for \(session.request.terminal.label).")
        }

        for windowID in session.windowIDs {
            try controller.closeWindow(windowID: windowID)
        }
    }

    private func validatedLaunchItems(from items: [LaunchItem]) throws -> [(tool: ToolDefinition, directory: String, count: Int)] {
        var resolved: [(tool: ToolDefinition, directory: String, count: Int)] = []

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

            resolved.append((tool: tool, directory: expandedDirectory, count: item.count))
        }

        if resolved.isEmpty {
            throw DispatchError.validation("Pick at least one tool instance.")
        }

        return resolved
    }

    private func makeLaunchCommand(directory: String, toolCommand: String) -> String {
        let shellBody = "cd \(Shell.singleQuote(directory)) && exec \(toolCommand)"
        return "zsh -lc \(Shell.singleQuote(shellBody))"
    }
}
