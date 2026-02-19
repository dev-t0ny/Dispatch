import Foundation

struct WindowBounds {
    let left: Int
    let top: Int
    let right: Int
    let bottom: Int
}

struct WindowTiler {
    private let margin: Double = 10
    private let gap: Double = 8

    func bounds(for count: Int, layout: LayoutPreset, screen: ScreenGeometry) -> [WindowBounds] {
        let (rows, cols) = gridDimensions(for: count, layout: layout, screen: screen)

        let availableWidth = max(100, screen.visibleFrame.width - (2 * margin) - (Double(cols - 1) * gap))
        let availableHeight = max(100, screen.visibleFrame.height - (2 * margin) - (Double(rows - 1) * gap))

        let cellWidth = floor(availableWidth / Double(cols))
        let cellHeight = floor(availableHeight / Double(rows))

        let visibleTop = screen.frame.maxY - screen.visibleFrame.maxY
        let originX = screen.visibleFrame.minX + margin
        let originTop = visibleTop + margin

        return (0..<count).map { index in
            let row = index / cols
            let col = index % cols

            let left = Int(originX + (Double(col) * (cellWidth + gap)))
            let top = Int(originTop + (Double(row) * (cellHeight + gap)))
            let right = Int(Double(left) + cellWidth)
            let bottom = Int(Double(top) + cellHeight)

            return WindowBounds(left: left, top: top, right: right, bottom: bottom)
        }
    }

    private func gridDimensions(for count: Int, layout: LayoutPreset, screen: ScreenGeometry) -> (Int, Int) {
        switch layout {
        case .adaptive:
            let aspect = max(0.5, screen.visibleFrame.width / max(screen.visibleFrame.height, 1))
            let cols = max(1, Int(ceil(sqrt(Double(count) * aspect))))
            let rows = Int(ceil(Double(count) / Double(cols)))
            return (rows, cols)
        case .balanced:
            return fitted(cols: 2, count: count)
        case .wide:
            return fitted(cols: 3, count: count)
        case .dense:
            return fitted(cols: 4, count: count)
        }
    }

    private func fitted(cols: Int, count: Int) -> (Int, Int) {
        let adjustedCols = max(1, cols)
        let rows = max(1, Int(ceil(Double(count) / Double(adjustedCols))))
        return (rows, adjustedCols)
    }
}
