import AppKit

/// Draws a rounded badge with the (remaining part of the) label for each hint
/// group — yellow for a single target, green for a cluster — and, when a
/// cluster is picked, a magnified panel of its area with normal badges on the
/// members. Flipped so its coordinates match AX frames.
final class HintOverlayView: NSView {
    /// Which way a badge's caret pointer aims — at the element below, above, or
    /// beside it, or nowhere (the badge overlaps what it labels, so a pointer
    /// would only mislead).
    enum CaretDirection {
        case downward, upward, leftward, rightward, hidden
    }

    struct Badge {
        let rect: CGRect
        let label: String
        /// What the badge labels, in the badge's own coordinate space: the
        /// caret aims at it, and a cluster's gets the translucent wash.
        let target: CGRect
        /// This badge stands for a whole cluster of targets: drawn green, its
        /// area washed, and its label opens the zoom.
        let isGroup: Bool
        let caret: CaretDirection

        init(rect: CGRect, label: String, target: CGRect, isGroup: Bool = false,
             caret: CaretDirection) {
            self.rect = rect
            self.label = label
            self.target = target
            self.isGroup = isGroup
            self.caret = caret
        }
    }

    /// The caret aims from the badge's final spot at the labeled frame; both
    /// rects just need to share a coordinate space.
    static func caretDirection(from badge: CGRect, toward area: CGRect) -> CaretDirection {
        if badge.maxY <= area.minY { return .downward }
        if badge.minY >= area.maxY { return .upward }
        if badge.maxX <= area.minX { return .rightward }
        if badge.minX >= area.maxX { return .leftward }
        return .hidden
    }

    /// Where along the badge's bottom (or top) edge the caret pointer sits.
    /// A target wider than the badge — hint mode's buttons and links — gets the
    /// pointer near the badge's leading edge, over the target's own corner. A
    /// target narrower than the badge — text jump's single glyphs — gets it
    /// aimed at the target's middle, since a fixed inset would have the pointer
    /// miss the character by most of a character. Always kept far enough inside
    /// the badge for the triangle's base to stay on the edge.
    static func caretAim(along badge: CGRect, at target: CGRect, halfBase: CGFloat) -> CGFloat {
        let aim = target.width < badge.width
            ? target.midX
            : badge.minX + min(8, badge.width / 2)
        return min(max(aim, badge.minX + halfBase + 1), badge.maxX - halfBase - 1)
    }

    /// The sideways caret's counterpart: down the badge's leading (or trailing)
    /// edge. Same rule, applied to height.
    static func caretAim(down badge: CGRect, at target: CGRect, halfBase: CGFloat) -> CGFloat {
        let aim = target.height < badge.height ? target.midY : badge.midY
        return min(max(aim, badge.minY + halfBase + 1), badge.maxY - halfBase - 1)
    }

    /// A scrollable pane scroll mode is showing. With a label, the pane is a
    /// candidate: washed, outlined, and badged in its center for picking. With
    /// no label it's the active pane being scrolled — outline only, so the
    /// content stays readable while it moves.
    struct Pane {
        let rect: CGRect
        let label: String?
    }

    struct Zoom {
        let panel: CGRect
        let canvas: CGRect
        let image: CGImage?
        /// Member frames magnified onto the canvas — the badge carets aim at
        /// them.
        let content: [CGRect]
        let badges: [Badge]
    }

    /// The target window's frame in view coordinates. The overlay covers the
    /// whole screen; the banner and the zoom's dimming stay over the window
    /// the hints belong to.
    var windowRegion: CGRect = .zero

    var badges: [Badge] = [] {
        didSet { needsDisplay = true }
    }

    var panes: [Pane] = [] {
        didSet { needsDisplay = true }
    }

    /// Letters typed so far; badges not matching this prefix disappear and the
    /// matched prefix renders dimmed on the rest.
    var typed: String = "" {
        didSet { needsDisplay = true }
    }

    /// A centered prompt drawn instead of (or alongside) badges — used to show a
    /// mode is armed and waiting.
    var banner: String? {
        didSet { needsDisplay = true }
    }

    /// When set, the group badges hide and this magnified panel draws instead.
    var zoom: Zoom? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    private static let fill = NSColor(calibratedRed: 1.0, green: 0.87, blue: 0.4, alpha: 0.95)
    private static let stroke = NSColor(calibratedRed: 0.5, green: 0.38, blue: 0.05, alpha: 0.9)
    private static let groupFill = NSColor(calibratedRed: 0.6, green: 0.9, blue: 0.5, alpha: 0.95)
    private static let groupStroke = NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.1, alpha: 0.9)
    private static let ink = NSColor.black
    private static let typedInk = NSColor.black.withAlphaComponent(0.35)

    override func draw(_ dirtyRect: NSRect) {
        if let zoom {
            drawZoom(zoom)
        } else {
            for pane in panes where pane.label?.hasPrefix(typed) ?? true {
                drawPane(pane)
            }
            let visible = badges.filter { $0.label.hasPrefix(typed) }
            // Areas go down first so a wash never dims a neighboring badge.
            for badge in visible where badge.isGroup {
                drawArea(badge.target)
            }
            for badge in visible {
                drawBadge(badge)
            }
        }
        if let banner {
            drawBanner(banner)
        }
    }

    private func drawZoom(_ zoom: Zoom) {
        // Dim the window so the panel is unmistakably the thing to read.
        NSColor.black.withAlphaComponent(0.25).setFill()
        windowRegion.intersection(bounds).fill(using: .sourceOver)

        let panel = NSBezierPath(roundedRect: zoom.panel, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.13, alpha: 0.98).setFill()
        panel.fill()

        // Zoom only opens with Screen Recording granted, so a nil image is a
        // rare capture failure; the badges still draw over the dark panel.
        if let image = zoom.image {
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(roundedRect: zoom.canvas, xRadius: 4, yRadius: 4).addClip()
            NSImage(cgImage: image, size: .zero).draw(
                in: zoom.canvas, from: .zero, operation: .sourceOver, fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high.rawValue]
            )
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        Self.stroke.setStroke()
        panel.lineWidth = 2
        panel.stroke()

        for badge in zoom.badges where badge.label.hasPrefix(typed) {
            drawBadge(badge)
        }
    }

    private func drawBanner(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: Self.ink
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let textSize = string.size()
        let padding = CGSize(width: 14, height: 8)
        let region = windowRegion.isEmpty ? bounds : windowRegion
        let pill = CGRect(
            x: region.midX - textSize.width / 2 - padding.width,
            y: region.minY + region.height * 0.12,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )
        let path = NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8)
        Self.fill.setFill()
        path.fill()
        Self.stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
        string.draw(at: CGPoint(x: pill.minX + padding.width, y: pill.minY + padding.height))
    }

    /// The outline sits just inside the pane's edge so neighboring panes'
    /// outlines never merge into one stroke.
    private func drawPane(_ pane: Pane) {
        let accent = NSColor.controlAccentColor
        let path = NSBezierPath(
            roundedRect: pane.rect.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6
        )
        if let label = pane.label {
            accent.withAlphaComponent(0.12).setFill()
            path.fill()
            accent.withAlphaComponent(0.7).setStroke()
            path.lineWidth = 2
            path.stroke()
            let size = BadgeMetrics.size(forLabelLength: label.count)
            let rect = CGRect(
                x: pane.rect.midX - size.width / 2, y: pane.rect.midY - size.height / 2,
                width: size.width, height: size.height
            )
            drawBadge(Badge(rect: rect, label: label, target: pane.rect, caret: .hidden))
        } else {
            accent.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 3
            path.stroke()
        }
    }

    /// A translucent green wash over a cluster's area, tying the group's one
    /// green badge to every target it stands for.
    private func drawArea(_ area: CGRect) {
        let path = NSBezierPath(
            roundedRect: area.insetBy(dx: -2, dy: -2), xRadius: 3, yRadius: 3
        )
        Self.groupFill.withAlphaComponent(0.25).setFill()
        path.fill()
        Self.groupStroke.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawBadge(_ badge: Badge) {
        let text = NSMutableAttributedString(
            string: badge.label.uppercased(),
            attributes: [.font: BadgeMetrics.font, .foregroundColor: Self.ink, .kern: BadgeMetrics.kern]
        )
        if !typed.isEmpty {
            text.addAttribute(
                .foregroundColor, value: Self.typedInk,
                range: NSRange(location: 0, length: typed.count)
            )
        }

        let fillColor = badge.isGroup ? Self.groupFill : Self.fill
        let strokeColor = badge.isGroup ? Self.groupStroke : Self.stroke
        let path = NSBezierPath(roundedRect: badge.rect, xRadius: 4, yRadius: 4)
        fillColor.setFill()
        path.fill()
        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        drawCaret(of: badge, fill: fillColor, stroke: strokeColor)
        let textSize = text.size()
        text.draw(at: CGPoint(
            x: badge.rect.midX - textSize.width / 2,
            y: badge.rect.midY - textSize.height / 2
        ))
    }

    /// A little triangular tail on the badge pointing at what it labels. Drawn
    /// after the badge stroke so its base seamlessly covers the border segment
    /// where the two shapes join. The view is flipped: `.down` means toward
    /// larger y.
    private func drawCaret(of badge: Badge, fill: NSColor, stroke: NSColor) {
        let halfBase: CGFloat = 4
        let rect = badge.rect

        // The caret's base sits on the badge edge facing the element, its tip
        // `caretHeight` beyond it; the base corners get tucked a point into the
        // badge so the fill hides the border between the two shapes.
        let base: CGPoint, tip: CGPoint, across: CGPoint, tuck: CGPoint
        switch badge.caret {
        case .hidden:
            return
        case .downward, .upward:
            let baseY = badge.caret == .downward ? rect.maxY : rect.minY
            let reach = badge.caret == .downward ? HintGeometry.caretHeight : -HintGeometry.caretHeight
            base = CGPoint(x: Self.caretAim(along: rect, at: badge.target, halfBase: halfBase), y: baseY)
            tip = CGPoint(x: base.x, y: baseY + reach)
            across = CGPoint(x: halfBase, y: 0)
            tuck = CGPoint(x: 0, y: badge.caret == .downward ? -1 : 1)
        case .rightward, .leftward:
            let baseX = badge.caret == .rightward ? rect.maxX : rect.minX
            let reach = badge.caret == .rightward ? HintGeometry.caretHeight : -HintGeometry.caretHeight
            base = CGPoint(x: baseX, y: Self.caretAim(down: rect, at: badge.target, halfBase: halfBase))
            tip = CGPoint(x: baseX + reach, y: base.y)
            across = CGPoint(x: 0, y: halfBase)
            tuck = CGPoint(x: badge.caret == .rightward ? -1 : 1, y: 0)
        }

        let body = NSBezierPath()
        body.move(to: CGPoint(x: base.x - across.x + tuck.x, y: base.y - across.y + tuck.y))
        body.line(to: tip)
        body.line(to: CGPoint(x: base.x + across.x + tuck.x, y: base.y + across.y + tuck.y))
        body.close()
        fill.setFill()
        body.fill()

        let edges = NSBezierPath()
        edges.move(to: CGPoint(x: base.x - across.x, y: base.y - across.y))
        edges.line(to: tip)
        edges.line(to: CGPoint(x: base.x + across.x, y: base.y + across.y))
        stroke.setStroke()
        edges.lineWidth = 1
        edges.stroke()
    }
}
