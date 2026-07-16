import CoreGraphics

/// Geometry for the zoomed view of one hint group: where the magnified panel
/// sits, how much it magnifies, and where the member frames and their labels
/// land inside it. Pure math in overlay-view coordinates, kept apart from the
/// drawing so it can be unit tested.
enum HintZoom {
    struct Layout {
        /// The whole panel, border included.
        let panel: CGRect
        /// Where the magnified area maps, inset within the panel — the
        /// screenshot (or member sketches) draw here.
        let canvas: CGRect
        let scale: CGFloat
        /// The member frames magnified onto the canvas, in input order.
        let content: [CGRect]
        /// One label spot per member: centered on its content rect when free,
        /// otherwise nudged the smallest distance that reads clearly.
        let badges: [CGRect]
    }

    private static let padding: CGFloat = 8
    private static let gap: CGFloat = 2
    private static let minScale: CGFloat = 2
    private static let maxScale: CGFloat = 6
    /// The panel may cover at most this much of the window.
    private static let maxCoverage: CGFloat = 0.9

    /// `area` is the region being magnified and `members` the target frames
    /// inside it, both in view coordinates. The panel centers over `area` and
    /// is kept inside `bounds`.
    static func layout(
        area: CGRect, members: [CGRect], badgeSize: CGSize, bounds: CGRect
    ) -> Layout {
        let scale = scale(for: members, badgeSize: badgeSize, area: area, bounds: bounds)
        var panel = CGRect(
            x: 0, y: 0,
            width: area.width * scale + padding * 2,
            height: area.height * scale + padding * 2
        )
        panel.origin.x = area.midX - panel.width / 2
        panel.origin.y = area.midY - panel.height / 2
        panel.origin.x = min(max(panel.minX, bounds.minX), max(bounds.minX, bounds.maxX - panel.width))
        panel.origin.y = min(max(panel.minY, bounds.minY), max(bounds.minY, bounds.maxY - panel.height))

        let canvas = panel.insetBy(dx: padding, dy: padding)
        let content = members.map { member in
            CGRect(
                x: canvas.minX + (member.minX - area.minX) * scale,
                y: canvas.minY + (member.minY - area.minY) * scale,
                width: member.width * scale,
                height: member.height * scale
            )
        }
        return Layout(
            panel: panel, canvas: canvas, scale: scale, content: content,
            badges: spread(badgeSize, over: content, within: panel)
        )
    }

    /// Magnifies until the two closest members sit a label's width apart, kept
    /// within taste (2–6x) and within what fits in the window.
    private static func scale(
        for members: [CGRect], badgeSize: CGSize, area: CGRect, bounds: CGRect
    ) -> CGFloat {
        var closest = CGFloat.greatestFiniteMagnitude
        for (index, lhs) in members.enumerated() {
            for rhs in members[(index + 1)...] {
                closest = min(closest, hypot(lhs.midX - rhs.midX, lhs.midY - rhs.midY))
            }
        }
        var scale = closest > 0 && closest < .greatestFiniteMagnitude
            ? (badgeSize.width + gap) / closest
            : maxScale
        scale = min(max(scale, minScale), maxScale)
        if area.width > 0 {
            scale = min(scale, (bounds.width * maxCoverage - padding * 2) / area.width)
        }
        if area.height > 0 {
            scale = min(scale, (bounds.height * maxCoverage - padding * 2) / area.height)
        }
        return max(scale, 1)
    }

    /// Greedy non-overlapping label spots: each label wants to hang off its
    /// magnified member's top-left corner; when members still crowd (concentric
    /// elements, say), it slides the smallest distance free, preferring
    /// straight up or down.
    private static func spread(
        _ size: CGSize, over content: [CGRect], within panel: CGRect
    ) -> [CGRect] {
        var taken: [CGRect] = []
        return content.map { rect in
            let ideal = HintGeometry.badgeRect(size, labeling: rect, in: panel)
            var spot = ideal
            if !isFree(ideal, avoiding: taken) {
                for offset in offsets(for: size) {
                    let candidate = clamped(
                        ideal.offsetBy(dx: offset.x, dy: offset.y), in: panel
                    )
                    if isFree(candidate, avoiding: taken) {
                        spot = candidate
                        break
                    }
                }
            }
            taken.append(spot)
            return spot
        }
    }

    /// Candidate displacements, nearest first, vertical preferred.
    private static func offsets(for size: CGSize) -> [CGPoint] {
        let stepY = size.height + gap
        let stepX = size.width / 2 + gap
        var offsets: [CGPoint] = []
        for row in 1...8 {
            for column in -4...4 {
                offsets.append(CGPoint(x: CGFloat(column) * stepX, y: -CGFloat(row) * stepY))
                offsets.append(CGPoint(x: CGFloat(column) * stepX, y: CGFloat(row) * stepY))
            }
        }
        return offsets.sorted { lhs, rhs in
            let (left, right) = (hypot(lhs.x * 2, lhs.y), hypot(rhs.x * 2, rhs.y))
            if left != right { return left < right }
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.x > rhs.x
        }
    }

    private static func isFree(_ candidate: CGRect, avoiding taken: [CGRect]) -> Bool {
        let padded = candidate.insetBy(dx: -gap / 2, dy: -gap / 2)
        return taken.allSatisfy { !$0.intersects(padded) }
    }

    private static func clamped(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        var rect = rect
        rect.origin.x = min(max(rect.minX, bounds.minX), max(bounds.minX, bounds.maxX - rect.width))
        rect.origin.y = min(max(rect.minY, bounds.minY), max(bounds.minY, bounds.maxY - rect.height))
        return rect
    }
}
