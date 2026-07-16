import CoreGraphics
import Foundation

/// Synthesizes real mouse clicks at a global screen point. CGEvent uses the same
/// top-left origin coordinate space that AX element frames are reported in, so
/// hint targets' click points can be used directly.
enum MouseClicker {
    enum Button: Sendable, Equatable {
        case left
        case right

        var opposite: Button { self == .left ? .right : .left }
    }

    /// Clicks after the mode's overlay has had a beat to leave the screen, so
    /// the click lands on the app's pixels rather than the departing badges.
    /// Every mode dismisses first and then calls this.
    @MainActor
    static func clickOnceOverlaySettles(at point: CGPoint, button: Button) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            click(at: point, button: button)
        }
    }

    static func click(at point: CGPoint, button: Button) {
        let phases: [CGEventType] = button == .left
            ? [.leftMouseDown, .leftMouseUp]
            : [.rightMouseDown, .rightMouseUp]
        let cgButton: CGMouseButton = button == .left ? .left : .right

        // Move the pointer first so the app's hover state agrees with where the
        // click lands (menus, tooltips, and web pages care).
        CGWarpMouseCursorPosition(point)

        let source = CGEventSource(stateID: .combinedSessionState)
        for kind in phases {
            let event = CGEvent(
                mouseEventSource: source, mouseType: kind,
                mouseCursorPosition: point, mouseButton: cgButton
            )
            event?.setIntegerValueField(.mouseEventClickState, value: 1)
            event?.post(tap: .cghidEventTap)
        }
    }
}
