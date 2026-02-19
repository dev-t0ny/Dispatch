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

    /// Mapping of agent UUID → terminal window ID for position tracking.
    private var agentWindowIDs: [UUID: Int] = [:]

    /// Timer for fast position tracking (independent of the 1.5s detection cycle).
    private var trackingTimer: Timer?

    /// Start a fast timer that updates overlay positions by reading window
    /// bounds from Core Graphics (no AppleScript overhead).
    func startTracking() {
        guard trackingTimer == nil else { return }
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateOverlayPositions()
            }
        }
    }

    /// Stop the position tracking timer.
    func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    /// Show or update a border overlay for the given agent, positioned around
    /// the terminal window bounds.
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

        let inset = Int(Self.borderWidth) + 1
        let frame = NSRect(
            x: bounds.left - inset,
            y: screenFlippedY(top: bounds.top, bottom: bounds.bottom) - inset,
            width: bounds.right - bounds.left + (inset * 2),
            height: bounds.bottom - bounds.top + (inset * 2)
        )

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

        // Start fast position tracking when first overlay appears.
        startTracking()
    }

    /// Hide and remove the overlay for a specific agent.
    func hideOverlay(for agentID: UUID) {
        guard let overlay = overlays.removeValue(forKey: agentID) else { return }
        overlay.orderOut(nil)
        agentWindowIDs.removeValue(forKey: agentID)

        // Stop tracking when no overlays are visible.
        if overlays.isEmpty { stopTracking() }
    }

    /// Hide all overlays (e.g. when session is closed).
    func hideAll() {
        for (_, overlay) in overlays {
            overlay.orderOut(nil)
        }
        overlays.removeAll()
        agentWindowIDs.removeAll()
        stopTracking()
    }

    // MARK: - Fast Position Tracking

    /// Query Core Graphics for current window positions and reposition overlays.
    /// This runs on a fast timer (~7fps) so overlays track window dragging smoothly.
    private func updateOverlayPositions() {
        guard !overlays.isEmpty else { return }

        // Get all on-screen windows from CG. This is a lightweight C call —
        // much faster than AppleScript.
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return }

        // Build a lookup: CG window number → bounds rect.
        // Note: CG window IDs and AppleScript window IDs may differ.
        // We match on window bounds from our last known snapshot to correlate.
        var cgBounds: [CGWindowID: CGRect] = [:]
        for entry in windowList {
            guard let wid = entry[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let w = boundsDict["Width"] as? CGFloat,
                  let h = boundsDict["Height"] as? CGFloat else { continue }
            cgBounds[wid] = CGRect(x: x, y: y, width: w, height: h)
        }

        // For each overlay, find the matching CG window and update position.
        for (agentID, overlay) in overlays {
            guard let terminalWindowID = agentWindowIDs[agentID] else { continue }

            // Try direct CG window ID match first.
            if let rect = cgBounds[CGWindowID(terminalWindowID)] {
                repositionOverlay(overlay, toWindowRect: rect)
                continue
            }

            // If no direct match (CG IDs can differ from AppleScript IDs),
            // find the closest match by comparing against overlay's current position.
            let overlayFrame = overlay.frame
            let currentCenter = CGPoint(
                x: overlayFrame.midX,
                y: NSScreen.screens.first.map { $0.frame.height - overlayFrame.midY } ?? overlayFrame.midY
            )

            var bestMatch: CGRect?
            var bestDist = CGFloat.greatestFiniteMagnitude
            for (_, rect) in cgBounds {
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let dist = hypot(center.x - currentCenter.x, center.y - currentCenter.y)
                if dist < bestDist && dist < 50 { // within 50pt
                    bestDist = dist
                    bestMatch = rect
                }
            }

            if let rect = bestMatch {
                repositionOverlay(overlay, toWindowRect: rect)
            }
        }
    }

    /// Reposition an overlay window to frame a CG window rect.
    /// The CG rect uses top-left origin; we convert to AppKit bottom-left.
    private func repositionOverlay(_ overlay: NSWindow, toWindowRect cgRect: CGRect) {
        let inset = Self.borderWidth + 1
        let appKitY = screenFlippedY(
            top: Int(cgRect.minY),
            bottom: Int(cgRect.maxY)
        )
        let frame = NSRect(
            x: CGFloat(Int(cgRect.minX)) - inset,
            y: CGFloat(appKitY) - inset,
            width: cgRect.width + (inset * 2),
            height: cgRect.height + (inset * 2)
        )

        if overlay.frame != frame {
            overlay.setFrame(frame, display: false, animate: false)
        }
    }

    /// Convert from AppleScript/Carbon bounds (top-left origin) to AppKit
    /// screen coordinates (bottom-left origin).
    private func screenFlippedY(top: Int, bottom: Int) -> Int {
        guard let screen = NSScreen.screens.first else { return top }
        let screenHeight = Int(screen.frame.height)
        return screenHeight - bottom
    }
}

// MARK: - Border-only NSView

/// Draws only a rounded-rect border stroke — no fill. This gives the thin
/// colored frame effect around the terminal window.
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
