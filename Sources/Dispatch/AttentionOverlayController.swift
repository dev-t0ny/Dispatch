import AppKit
import CoreGraphics
import Foundation

/// Manages thin colored border overlays that sit on top of terminal windows
/// to subtly indicate when an agent needs human attention.
@MainActor
final class AttentionOverlayController {

    private static let borderWidth: CGFloat = 3
    private static let cornerRadius: CGFloat = 8

    /// One overlay per agent (keyed by agent UUID).
    private var overlays: [UUID: NSWindow] = [:]

    /// Mapping of agent UUID -> AppleScript window ID for position tracking.
    private var agentWindowIDs: [UUID: Int] = [:]

    /// The terminal app name to filter CG windows (e.g. "iTerm2", "Terminal").
    var terminalAppName: String = "iTerm2"

    /// Timer for fast position tracking.
    private var trackingTimer: Timer?

    // MARK: - Public API

    /// Show or update a border overlay for the given agent.
    func showOverlay(for agentID: UUID, windowID: Int, bounds: WindowBounds, state: AgentState) {
        agentWindowIDs[agentID] = windowID

        let color: NSColor
        switch state {
        case .needsInput:
            color = NSColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 0.85)  // amber
        case .blocked:
            color = NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 0.85)  // red
        default:
            hideOverlay(for: agentID)
            return
        }

        let frame = overlayFrame(for: bounds)

        if let existing = overlays[agentID] {
            existing.setFrame(frame, display: false, animate: false)
            if let borderView = existing.contentView?.subviews.first as? BorderView {
                borderView.borderColor = color
                borderView.setNeedsDisplay(borderView.bounds)
            }
            existing.orderFront(nil)
            return
        }

        let overlay = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.level = .floating
        overlay.ignoresMouseEvents = true
        overlay.hasShadow = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let borderView = BorderView(frame: overlay.contentView!.bounds)
        borderView.borderColor = color
        borderView.borderWidth = Self.borderWidth
        borderView.cornerRadius = Self.cornerRadius
        borderView.autoresizingMask = [.width, .height]
        overlay.contentView?.addSubview(borderView)

        overlay.orderFront(nil)
        overlays[agentID] = overlay

        startTracking()
    }

    func hideOverlay(for agentID: UUID) {
        guard let overlay = overlays.removeValue(forKey: agentID) else { return }
        overlay.orderOut(nil)
        agentWindowIDs.removeValue(forKey: agentID)
        if overlays.isEmpty { stopTracking() }
    }

    func hideAll() {
        for (_, overlay) in overlays {
            overlay.orderOut(nil)
        }
        overlays.removeAll()
        agentWindowIDs.removeAll()
        stopTracking()
    }

    // MARK: - Fast Position Tracking

    private func startTracking() {
        guard trackingTimer == nil else { return }
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateOverlayPositions()
            }
        }
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    /// Read current window positions from Core Graphics and reposition overlays.
    private func updateOverlayPositions() {
        guard !overlays.isEmpty else { return }

        // Build a lookup of CG window ID -> bounds for the terminal app.
        let cgWindows = terminalWindowBounds()

        for (agentID, overlay) in overlays {
            guard let windowID = agentWindowIDs[agentID],
                  let cgRect = cgWindows[windowID] else { continue }

            let frame = overlayFrame(forCGRect: cgRect)
            if overlay.frame != frame {
                overlay.setFrame(frame, display: false, animate: false)
            }
        }
    }

    /// Get all on-screen windows for the terminal app via Core Graphics.
    /// Returns [CG window number: CGRect in screen coordinates (top-left origin)].
    private func terminalWindowBounds() -> [Int: CGRect] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [:] }

        var result: [Int: CGRect] = [:]
        for entry in windowList {
            guard let owner = entry[kCGWindowOwnerName as String] as? String,
                  owner == terminalAppName,
                  let wid = entry[kCGWindowNumber as String] as? Int,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"],
                  let y = boundsDict["Y"],
                  let w = boundsDict["Width"],
                  let h = boundsDict["Height"],
                  w > 50, h > 50  // filter out sub-windows (tab bar, etc.)
            else { continue }

            result[wid] = CGRect(x: x, y: y, width: w, height: h)
        }
        return result
    }

    // MARK: - Geometry Helpers

    /// Build overlay NSRect from AppleScript-style WindowBounds (top-left origin).
    private func overlayFrame(for bounds: WindowBounds) -> NSRect {
        let inset = Self.borderWidth + 1
        let appKitY = CGFloat(screenFlippedY(top: bounds.top, bottom: bounds.bottom))
        return NSRect(
            x: CGFloat(bounds.left) - inset,
            y: appKitY - inset,
            width: CGFloat(bounds.right - bounds.left) + (inset * 2),
            height: CGFloat(bounds.bottom - bounds.top) + (inset * 2)
        )
    }

    /// Build overlay NSRect from a CG rect (top-left origin).
    private func overlayFrame(forCGRect cgRect: CGRect) -> NSRect {
        let inset = Self.borderWidth + 1
        let appKitY = CGFloat(screenFlippedY(top: Int(cgRect.minY), bottom: Int(cgRect.maxY)))
        return NSRect(
            x: cgRect.minX - inset,
            y: appKitY - inset,
            width: cgRect.width + (inset * 2),
            height: cgRect.height + (inset * 2)
        )
    }

    /// Convert from top-left origin to AppKit bottom-left origin.
    private func screenFlippedY(top: Int, bottom: Int) -> Int {
        guard let screen = NSScreen.screens.first else { return top }
        let screenHeight = Int(screen.frame.height)
        return screenHeight - bottom
    }
}

// MARK: - Border-only NSView

private class BorderView: NSView {
    var borderColor: NSColor = .orange
    var borderWidth: CGFloat = 3
    var cornerRadius: CGFloat = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = borderWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        path.lineWidth = borderWidth
        borderColor.setStroke()
        path.stroke()
    }
}
