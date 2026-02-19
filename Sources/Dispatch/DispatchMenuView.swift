import AppKit
import SwiftUI

struct DispatchMenuView: View {
    @ObservedObject var viewModel: DispatchViewModel

    private let layoutColumns = [
        GridItem(.flexible(minimum: 120), spacing: 8),
        GridItem(.flexible(minimum: 120), spacing: 8)
    ]
    private let runtimeRefreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            terminalPicker
            launchRowsSection
            screenSection
            layoutSection
            controls
            activeTerminalsSection
            presetsSection

            if let status = viewModel.status {
                Text(status.text)
                    .font(.caption)
                    .foregroundStyle(color(for: status.level))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Quit Dispatch") {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 620)
        .onAppear {
            viewModel.refreshRuntimeContext(silent: true)
        }
        .onChange(of: viewModel.selectedTerminal) { _ in
            viewModel.refreshRuntimeContext(silent: false)
        }
        .onReceive(runtimeRefreshTimer) { _ in
            viewModel.refreshRuntimeContext(silent: true)
        }
    }

    private var header: some View {
        HStack {
            Text("Dispatch")
                .font(.title3.bold())
            Spacer()

            Text("Windows")
                .font(.caption)

            TextField("0", value: totalCountBinding, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)

            Stepper("", value: totalCountBinding, in: 0...240)
                .labelsHidden()
        }
    }

    private var terminalPicker: some View {
        Picker("Terminal", selection: $viewModel.selectedTerminal) {
            ForEach(TerminalApp.allCases) { terminal in
                Text(terminal.label).tag(terminal)
            }
        }
        .pickerStyle(.segmented)
    }

    private var launchRowsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Launch Plan")
                    .font(.headline)
                Spacer()
                Button("Add Terminal") {
                    viewModel.addTerminal()
                }
            }

            ForEach(viewModel.launchRows) { row in
                HStack(spacing: 8) {
                    Picker("Tool", selection: toolBinding(for: row.id)) {
                        ForEach(viewModel.tools) { tool in
                            Text(tool.name).tag(tool.id)
                        }
                    }
                    .frame(width: 140)

                    TextField("Directory", text: directoryBinding(for: row.id))
                        .textFieldStyle(.roundedBorder)

                    Button("Choose") {
                        viewModel.chooseDirectory(for: row.id)
                    }

                    TextField("0", value: countBinding(for: row.id), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 42)

                    Stepper("", value: countBinding(for: row.id), in: 0...24)
                        .labelsHidden()

                    Button {
                        viewModel.removeRow(row.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layout")
                .font(.headline)

            LazyVGrid(columns: layoutColumns, spacing: 8) {
                ForEach(LayoutPreset.allCases) { option in
                    layoutCard(option)
                }
            }
        }
    }

    private var screenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screens")
                .font(.headline)

            if viewModel.availableScreens.isEmpty {
                Text("No displays detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScreenSelectionMap(
                    screens: viewModel.availableScreens
                )
                .frame(height: 120)

                Text("Display map only. Terminal detection runs in the background.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button("Launch") {
                viewModel.launchCurrent()
            }
            .keyboardShortcut(.return)

            Button("Relaunch Last") {
                viewModel.relaunchLast()
            }

            Button("Close Launched") {
                viewModel.closeLaunched()
            }

            Button("Focus Next Alert") {
                viewModel.focusNextAttention()
            }
        }
    }

    private var activeTerminalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Active Terminals")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.activeAgents.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.needsAttentionAgents.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("\(viewModel.needsAttentionAgents.count) terminal(s) need human attention")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Focus Next") {
                        viewModel.focusNextAttention()
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.yellow.opacity(0.16))
                )
            }

            if viewModel.activeAgents.isEmpty {
                Text("No tracked terminals yet. Launch one and Dispatch will detect existing windows automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.activeAgents) { agent in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(color(for: agent.tone))
                                    .frame(width: 9, height: 9)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(agent.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(agent.objective.isEmpty ? "No objective" : agent.objective)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Text(agent.state.label)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .foregroundStyle(stateColor(for: agent.state))
                                    .background(
                                        Capsule()
                                            .fill(stateColor(for: agent.state).opacity(0.16))
                                    )

                                Picker("", selection: stateBinding(for: agent.id)) {
                                    ForEach(AgentState.allCases) { state in
                                        Text(state.label).tag(state)
                                    }
                                }
                                .frame(width: 120)

                                Button(agent.state == .needsInput ? "Mark Running" : "Needs Input") {
                                    viewModel.setAgentState(agent.state == .needsInput ? .running : .needsInput, for: agent.id)
                                }
                                .controlSize(.small)

                                Button("Focus") {
                                    viewModel.focusAgent(agent.id)
                                }
                            }
                            .padding(7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(stateBackground(for: agent.state))
                            )
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack(spacing: 8) {
                TextField("Preset name", text: $viewModel.presetName)
                    .textFieldStyle(.roundedBorder)
                Button("Save Preset") {
                    viewModel.savePreset()
                }
            }

            if viewModel.presets.isEmpty {
                Text("No presets saved yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.presets) { preset in
                            HStack(spacing: 8) {
                                Button(preset.name) {
                                    viewModel.launchPreset(preset)
                                }
                                .buttonStyle(.link)

                                Spacer()

                                Text("\(preset.request.totalCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Button {
                                    viewModel.deletePreset(preset)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: 130)
            }
        }
    }

    private func layoutCard(_ option: LayoutPreset) -> some View {
        Button {
            viewModel.layout = option
        } label: {
            HStack(spacing: 8) {
                LayoutPreview(layout: option)
                    .frame(width: 44, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                    Text(option.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(viewModel.layout == option ? Color.accentColor.opacity(0.16) : Color.gray.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(viewModel.layout == option ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func toolBinding(for rowID: UUID) -> Binding<String> {
        Binding(
            get: {
                viewModel.launchRows.first(where: { $0.id == rowID })?.toolID ?? (viewModel.tools.first?.id ?? "claude")
            },
            set: { value in
                viewModel.updateTool(rowID: rowID, toolID: value)
            }
        )
    }

    private func directoryBinding(for rowID: UUID) -> Binding<String> {
        Binding(
            get: {
                viewModel.launchRows.first(where: { $0.id == rowID })?.directory ?? ""
            },
            set: { value in
                viewModel.updateDirectory(rowID: rowID, directory: value)
            }
        )
    }

    private func countBinding(for rowID: UUID) -> Binding<Int> {
        Binding(
            get: {
                viewModel.launchRows.first(where: { $0.id == rowID })?.count ?? 0
            },
            set: { value in
                viewModel.updateCount(rowID: rowID, count: value)
            }
        )
    }

    private func stateBinding(for agentID: UUID) -> Binding<AgentState> {
        Binding(
            get: {
                viewModel.activeAgents.first(where: { $0.id == agentID })?.state ?? .running
            },
            set: { value in
                viewModel.setAgentState(value, for: agentID)
            }
        )
    }

    private func color(for level: StatusLevel) -> Color {
        switch level {
        case .info:
            return .secondary
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private func color(for tone: AgentTone) -> Color {
        Color(hex: tone.hex)
    }

    private func stateColor(for state: AgentState) -> Color {
        switch state {
        case .running:
            return Color(hex: "#22C55E")
        case .needsInput:
            return Color(hex: "#F59E0B")
        case .blocked:
            return Color(hex: "#EF4444")
        case .done:
            return Color(hex: "#60A5FA")
        }
    }

    private func stateBackground(for state: AgentState) -> Color {
        switch state {
        case .running:
            return Color(hex: "#22C55E").opacity(0.09)
        case .needsInput:
            return Color(hex: "#F59E0B").opacity(0.12)
        case .blocked:
            return Color(hex: "#EF4444").opacity(0.12)
        case .done:
            return Color(hex: "#60A5FA").opacity(0.10)
        }
    }

    private var totalCountBinding: Binding<Int> {
        Binding(
            get: {
                viewModel.totalInstances
            },
            set: { value in
                viewModel.setTotalInstances(value)
            }
        )
    }
}

private extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: value).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

private struct ScreenSelectionMap: View {
    let screens: [DisplayTarget]

    var body: some View {
        GeometryReader { proxy in
            let screenRects = rectangles(for: screens, in: proxy.size)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.09))

                ForEach(Array(screens.enumerated()), id: \.element.id) { index, screen in
                    if let rect = screenRects[screen.id] {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.18))

                            VStack(spacing: 2) {
                                Text("Display \(index + 1)")
                                    .font(.caption2.weight(.semibold))
                                Text(sizeLabel(screen))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(4)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.45), lineWidth: 1)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
        }
    }

    private func sizeLabel(_ screen: DisplayTarget) -> String {
        let width = Int(screen.geometry.frame.width)
        let height = Int(screen.geometry.frame.height)
        return "\(width)x\(height)"
    }

    private func rectangles(for screens: [DisplayTarget], in size: CGSize) -> [String: CGRect] {
        guard !screens.isEmpty else { return [:] }

        let frames = screens.map(\.geometry.frame)
        let minX = frames.map(\.minX).min() ?? 0
        let minY = frames.map(\.minY).min() ?? 0
        let maxX = frames.map(\.maxX).max() ?? 1
        let maxY = frames.map(\.maxY).max() ?? 1

        let totalWidth = max(1, maxX - minX)
        let totalHeight = max(1, maxY - minY)

        let padding: CGFloat = 8
        let usableWidth = max(1, size.width - (padding * 2))
        let usableHeight = max(1, size.height - (padding * 2))

        let scaleX = usableWidth / totalWidth
        let scaleY = usableHeight / totalHeight
        let scale = min(scaleX, scaleY)

        let contentWidth = totalWidth * scale
        let contentHeight = totalHeight * scale
        let offsetX = (size.width - contentWidth) / 2
        let offsetY = (size.height - contentHeight) / 2

        var output: [String: CGRect] = [:]
        for screen in screens {
            let frame = screen.geometry.frame
            let x = offsetX + (frame.minX - minX) * scale
            let y = offsetY + (maxY - frame.maxY) * scale
            let rect = CGRect(x: x, y: y, width: frame.width * scale, height: frame.height * scale)
            output[screen.id] = rect.insetBy(dx: 2, dy: 2)
        }

        return output
    }
}

private struct LayoutPreview: View {
    let layout: LayoutPreset

    var body: some View {
        GeometryReader { proxy in
            let rects = rectangles(in: proxy.size)
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.gray.opacity(0.12))
                ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.65))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
    }

    private func rectangles(in size: CGSize) -> [CGRect] {
        let padding: CGFloat = 4
        let width = size.width - (padding * 2)
        let height = size.height - (padding * 2)
        switch layout {
        case .adaptive:
            return grid(cols: 2, rows: 2, width: width, height: height, padding: padding)
        case .balanced:
            return grid(cols: 2, rows: 1, width: width, height: height, padding: padding)
        case .wide:
            return grid(cols: 3, rows: 1, width: width, height: height, padding: padding)
        case .dense:
            return grid(cols: 4, rows: 2, width: width, height: height, padding: padding)
        }
    }

    private func grid(cols: Int, rows: Int, width: CGFloat, height: CGFloat, padding: CGFloat) -> [CGRect] {
        let gap: CGFloat = 2
        let cellWidth = (width - (CGFloat(cols - 1) * gap)) / CGFloat(cols)
        let cellHeight = (height - (CGFloat(rows - 1) * gap)) / CGFloat(rows)
        var rects: [CGRect] = []

        for row in 0..<rows {
            for col in 0..<cols {
                let x = padding + CGFloat(col) * (cellWidth + gap)
                let y = padding + CGFloat(row) * (cellHeight + gap)
                rects.append(CGRect(x: x, y: y, width: cellWidth, height: cellHeight))
            }
        }

        return rects
    }
}
