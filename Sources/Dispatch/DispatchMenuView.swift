import SwiftUI

struct DispatchMenuView: View {
    @ObservedObject var viewModel: DispatchViewModel

    private let layoutColumns = [
        GridItem(.flexible(minimum: 120), spacing: 8),
        GridItem(.flexible(minimum: 120), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            terminalPicker
            launchRowsSection
            layoutSection
            controls
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
        .frame(width: 560)
    }

    private var header: some View {
        HStack {
            Text("Dispatch")
                .font(.title3.bold())
            Spacer()
            Text("\(viewModel.totalInstances) total")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Button("Add Row") {
                    viewModel.addRow()
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

                    Stepper(value: countBinding(for: row.id), in: 0...24) {
                        Text("\(row.count)")
                            .frame(width: 24)
                    }
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
