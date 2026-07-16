import CoreGraphics

/// A clickable element found in the frontmost window.
struct HintTarget: Equatable {
    /// The element's visible frame in AX coordinates (global, top-left origin),
    /// already clipped to the window, so the center is a safe place to click.
    let frame: CGRect

    /// The element's AX role, when known — coalescing treats text inputs
    /// specially.
    let role: String?

    init(frame: CGRect, role: String? = nil) {
        self.frame = frame
        self.role = role
    }

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

    /// Two frames that are really the same click: each one's center sits inside
    /// the other, and they overlap by at least half their combined footprint.
    /// That collapses a link and the padded wrapper around it, but keeps a
    /// large card and a small button inside it (tiny overlap ratio) distinct.
    static func isSameClick(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        guard lhs.contains(CGPoint(x: rhs.midX, y: rhs.midY)),
              rhs.contains(CGPoint(x: lhs.midX, y: lhs.midY)) else { return false }
        let intersection = lhs.intersection(rhs)
        let overlap = intersection.width * intersection.height
        let union = lhs.width * lhs.height + rhs.width * rhs.height - overlap
        return union > 0 && overlap / union >= 0.5
    }

    /// Text inputs stay hintable even when other targets sit inside their
    /// frame — dropping a search field because it contains a clear button
    /// would make the field itself unreachable.
    static let containerExemptRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

    /// Drops targets that duplicate a click the user already has. Two passes:
    ///
    /// 1. Same-click twins — near-identical frames like a button and the padded
    ///    link around it — collapse to the smallest, whose center is inside
    ///    every wrapper, so clicking it presses them all.
    /// 2. Clickable containers — a sidebar row around its channel link, a
    ///    button around its icon image, a pressable card around its content —
    ///    are dropped whenever their frame wholly contains another surviving
    ///    target: the inner element is what the user means, and a container's
    ///    own center often lands on nothing visible at all. Text inputs are
    ///    exempt (see `containerExemptRoles`).
    ///
    /// Scan order is preserved for the survivors.
    static func coalesced(_ targets: [HintTarget]) -> [HintTarget] {
        let smallestFirst = targets.indices.sorted {
            targets[$0].frame.width * targets[$0].frame.height
                < targets[$1].frame.width * targets[$1].frame.height
        }
        var kept: [Int] = []
        for index in smallestFirst
        where !kept.contains(where: { isSameClick(targets[$0].frame, targets[index].frame) }) {
            kept.append(index)
        }

        let twins = kept.sorted().map { targets[$0] }
        return twins.filter { candidate in
            if let role = candidate.role, containerExemptRoles.contains(role) { return true }
            return !twins.contains { other in
                other != candidate && wrapsAround(candidate.frame, other.frame)
            }
        }
    }

    /// Whether `outer` is a container around `inner`: wholly contains it (with
    /// a point of slack for rounding) and is genuinely bigger — same-click
    /// twins have already been collapsed by the time this runs.
    private static func wrapsAround(_ outer: CGRect, _ inner: CGRect) -> Bool {
        outer.insetBy(dx: -1, dy: -1).contains(inner)
            && outer.width * outer.height > inner.width * inner.height
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
    /// Height of the caret pointer drawn between a badge and what it labels.
    static let caretHeight: CGFloat = 5

    /// Where a badge of `size` sits for an element at `area`: hanging above the
    /// element's top-left corner, caret pointing down at it, so the label
    /// covers as little of the element as possible. Flips underneath the
    /// element when the top of `bounds` leaves no room, and is always kept
    /// inside `bounds`.
    static func badgeRect(_ size: CGSize, labeling area: CGRect, in bounds: CGRect) -> CGRect {
        var rect = CGRect(
            x: area.minX,
            y: area.minY - size.height - caretHeight,
            width: size.width,
            height: size.height
        )
        if rect.minY < bounds.minY {
            rect.origin.y = area.maxY + caretHeight
        }
        rect.origin.x = min(max(rect.minX, bounds.minX), max(bounds.minX, bounds.maxX - rect.width))
        rect.origin.y = min(max(rect.minY, bounds.minY), max(bounds.minY, bounds.maxY - rect.height))
        return rect
    }

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
