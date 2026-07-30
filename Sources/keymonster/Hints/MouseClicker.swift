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

    /// Like `clickOnceOverlaySettles`, but puts the pointer back where it
    /// started once the click has landed. For modes whose click is only a
    /// caret-placement vehicle, not a destination the user meant to point at.
    ///
    /// The restore waits its own beat: the posted click events each carry the
    /// click point, and if the warp raced ahead of the window server processing
    /// them, they would drag the pointer right back to the field.
    @MainActor
    static func clickOnceOverlaySettlesThenRestorePointer(at point: CGPoint, button: Button) {
        let original = CGEvent(source: nil)?.location
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            click(at: point, button: button)
            guard let original else { return }
            try? await Task.sleep(for: .milliseconds(50))
            CGWarpMouseCursorPosition(original)
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
