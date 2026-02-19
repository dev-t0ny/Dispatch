import AppKit
import Foundation

/// Manages transparent overlay windows that sit on top of terminal windows
/// to visually indicate when an agent needs human attention.
@MainActor
final class AttentionOverlayController {

    /// One overlay per agent (keyed by agent UUID).
    private var overlays: [UUID: NSWindow] = [:]

    /// Show or update an overlay for the given agent, positioned over the
    /// terminal window bounds. The overlay is a soft translucent color.
    func showOverlay(for agentID: UUID, bounds: WindowBounds, state: AgentState) {
        let color: NSColor
        switch state {
        case .needsInput:
            color = NSColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 0.15)  // amber
        case .blocked:
            color = NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 0.15)  // red
        default:
            // No overlay for running/done states — hide instead.
            hideOverlay(for: agentID)
            return
        }

        let frame = NSRect(
            x: bounds.left,
            y: screenFlippedY(top: bounds.top, bottom: bounds.bottom),
            width: bounds.right - bounds.left,
            height: bounds.bottom - bounds.top
        )

        if let existing = overlays[agentID] {
            existing.setFrame(frame, display: true)
            existing.contentView?.layer?.backgroundColor = color.cgColor
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

        let view = NSView(frame: overlay.contentView!.bounds)
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.autoresizingMask = [.width, .height]
        overlay.contentView?.addSubview(view)

        overlay.orderFront(nil)
        overlays[agentID] = overlay
    }

    /// Hide and remove the overlay for a specific agent.
    func hideOverlay(for agentID: UUID) {
        guard let overlay = overlays.removeValue(forKey: agentID) else { return }
        overlay.orderOut(nil)
    }

    /// Hide all overlays (e.g. when session is closed).
    func hideAll() {
        for (_, overlay) in overlays {
            overlay.orderOut(nil)
        }
        overlays.removeAll()
    }

    /// Convert from AppleScript/Carbon bounds (top-left origin) to AppKit
    /// screen coordinates (bottom-left origin).
    private func screenFlippedY(top: Int, bottom: Int) -> Int {
        guard let screen = NSScreen.screens.first else { return top }
        let screenHeight = Int(screen.frame.height)
        return screenHeight - bottom
    }
}
