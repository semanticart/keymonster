import CoreGraphics

/// A clickable element found in the frontmost window.
struct HintTarget: Equatable {
    /// The element's visible frame in AX coordinates (global, top-left origin),
    /// already clipped to the window, so the center is a safe place to click.
    let frame: CGRect

    /// Where a synthesized click should land. CGEvent uses the same top-left
    /// origin global space as AX, so no conversion is needed.
    var clickPoint: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
}

/// Heuristics for which AX elements deserve a hint. Pure so they're testable
/// without a live accessibility tree.
enum HintTargetFilter {
    /// Roles that are clickable by nature, even when the app doesn't list an
    /// explicit press action for them.
    static let clickableRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton",
        "AXMenuButton", "AXMenuItem", "AXMenuBarItem", "AXComboBox",
        "AXTextField", "AXTextArea", "AXSlider", "AXIncrementor",
        "AXDisclosureTriangle", "AXColorWell", "AXRow"
    ]

    /// Actions that mark an otherwise-generic element (web `AXGroup`s, custom
    /// views) as clickable.
    static let clickableActions: Set<String> = [
        "AXPress", "AXOpen", "AXConfirm", "AXPick", "AXShowMenu"
    ]

    static func isClickable(role: String?, actions: [String]) -> Bool {
        if let role, clickableRoles.contains(role) { return true }
        return actions.contains { clickableActions.contains($0) }
    }

    /// Whether an element's frame is worth hinting: actually on screen inside
    /// its window, big enough to click, and not a window-sized container.
    static func isVisible(frame: CGRect, within window: CGRect) -> Bool {
        guard frame.width >= 4, frame.height >= 4 else { return false }
        guard frame.intersects(window) else { return false }
        // Elements as big as the window itself (web areas, root groups) are
        // containers; a hint centered on them would be noise.
        if frame.width >= window.width * 0.95 && frame.height >= window.height * 0.95 {
            return false
        }
        return true
    }
}

enum HintGeometry {
    /// AX reports global frames with a top-left origin; Cocoa windows use a
    /// bottom-left origin anchored to the primary screen. Converts between the
    /// two given the primary screen's height.
    static func cocoaRect(fromAX rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
