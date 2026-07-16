import AppKit

/// Shows hint badges in a transparent, click-through window covering the
/// screen the frontmost app's focused window is on — badges for elements at
/// the window's edge may hang just outside it.
@MainActor
final class HintOverlay {
    private var window: NSWindow?
    private var view: HintOverlayView?
    /// AX (top-left origin) coordinates of the overlay window's own origin —
    /// what to subtract to make a global AX rect view-local.
    private var origin: CGPoint = .zero

    /// `windowFrame` is the target window's frame in AX (top-left origin)
    /// coordinates — the same space the groups' frames are in. Single-member
    /// groups draw a normal badge; clusters draw a green area badge.
    func show(groups: [HintGrouping.Group], labels: [String], windowFrame: CGRect) {
        guard let view = install(around: windowFrame) else { return }
        // Badge rects become view-local (the view is flipped, so it shares the
        // AX tree's top-left origin — only the overlay's origin needs removing).
        view.badges = zip(groups, labels).map { group, label in
            HintOverlayView.Badge(
                rect: group.badge.offsetBy(dx: -origin.x, dy: -origin.y),
                label: label,
                isGroup: group.isCluster,
                caret: HintOverlayView.caretDirection(from: group.badge, toward: group.area)
            )
        }
    }

    /// Shows a centered message over the window with no hints — used to signal
    /// that a mode is armed and waiting for input.
    func showBanner(_ text: String, windowFrame: CGRect) {
        install(around: windowFrame)?.banner = text
    }

    /// Magnifies `area` (AX coordinates) in a panel over the same window, with
    /// one normal badge per member frame. `image` is the screenshot to magnify;
    /// nil sketches the member outlines instead. Call while the overlay is
    /// already showing; `clearZoom` restores the group badges untouched.
    func showZoom(area: CGRect, image: CGImage?, memberFrames: [CGRect], labels: [String]) {
        guard let view else { return }
        func local(_ rect: CGRect) -> CGRect {
            rect.offsetBy(dx: -origin.x, dy: -origin.y)
        }
        let layout = HintZoom.layout(
            area: local(area),
            members: memberFrames.map(local),
            badgeSize: HintOverlayView.badgeSize(forLabelLength: labels.first?.count ?? 1),
            bounds: view.bounds
        )
        view.typed = ""
        view.zoom = HintOverlayView.Zoom(
            panel: layout.panel,
            canvas: layout.canvas,
            image: image,
            content: layout.content,
            badges: layout.badges.indices.map { index in
                HintOverlayView.Badge(
                    rect: layout.badges[index],
                    label: labels[index],
                    isGroup: false,
                    caret: HintOverlayView.caretDirection(
                        from: layout.badges[index], toward: layout.content[index]
                    )
                )
            }
        )
    }

    /// Leaves the zoom and reveals the group badges again.
    func clearZoom() {
        view?.zoom = nil
        view?.typed = ""
    }

    /// What's on screen beneath the overlay in `area` (AX coordinates) — the
    /// app's own pixels, without our badges. Nil without Screen Recording
    /// permission.
    func snapshotBelow(area: CGRect) -> CGImage? {
        WindowCapture.below(window, bounds: area)
    }

    /// Lays a fresh transparent, click-through overlay window over the screen
    /// containing the target window and returns its view, or nil if there's no
    /// screen.
    @discardableResult
    private func install(around windowFrame: CGRect) -> HintOverlayView? {
        hide()
        guard let primary = NSScreen.screens.first else { return nil }
        let frame = HintScreens.bounds(around: windowFrame)
        let cocoaFrame = HintGeometry.cocoaRect(
            fromAX: frame, primaryScreenHeight: primary.frame.height
        )

        let window = NSWindow(
            contentRect: cocoaFrame, styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isReleasedWhenClosed = false

        let view = HintOverlayView(frame: CGRect(origin: .zero, size: cocoaFrame.size))
        view.windowRegion = windowFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        window.contentView = view
        window.orderFrontRegardless()

        self.window = window
        self.view = view
        self.origin = frame.origin
        return view
    }

    func update(typed: String) {
        view?.typed = typed
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        view = nil
    }
}

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
        /// Green: this badge stands for a whole area and opens the zoom.
        let isGroup: Bool
        let caret: CaretDirection
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

    struct Zoom {
        let panel: CGRect
        let canvas: CGRect
        let image: CGImage?
        /// Member frames magnified onto the canvas — sketched when there is no
        /// screenshot to show.
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

    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    private static let fill = NSColor(calibratedRed: 1.0, green: 0.87, blue: 0.4, alpha: 0.95)
    private static let stroke = NSColor(calibratedRed: 0.5, green: 0.38, blue: 0.05, alpha: 0.9)
    private static let groupFill = NSColor(calibratedRed: 0.6, green: 0.9, blue: 0.5, alpha: 0.95)
    private static let groupStroke = NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.1, alpha: 0.9)
    private static let ink = NSColor.black
    private static let typedInk = NSColor.black.withAlphaComponent(0.35)
    private static let padding = CGSize(width: 5, height: 2)

    /// How big a badge with a label of `length` letters draws — used to lay
    /// badges out before the labels themselves exist. The font is monospaced,
    /// so only the length matters.
    static func badgeSize(forLabelLength length: Int) -> CGSize {
        let sample = NSAttributedString(
            string: String(repeating: "W", count: max(1, length)),
            attributes: [.font: font, .kern: 0.5]
        )
        let textSize = sample.size()
        return CGSize(
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        if let zoom {
            drawZoom(zoom)
        } else {
            for badge in badges where badge.label.hasPrefix(typed) {
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

        if let image = zoom.image {
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(roundedRect: zoom.canvas, xRadius: 4, yRadius: 4).addClip()
            NSImage(cgImage: image, size: .zero).draw(
                in: zoom.canvas, from: .zero, operation: .sourceOver, fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high.rawValue]
            )
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            // No screenshot (Screen Recording permission missing): sketch the
            // members so their arrangement still reads.
            for rect in zoom.content {
                let box = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                NSColor(calibratedWhite: 0.3, alpha: 1).setFill()
                box.fill()
                Self.fill.setStroke()
                box.lineWidth = 1
                box.stroke()
            }
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

    private func drawBadge(_ badge: Badge) {
        let text = NSMutableAttributedString(
            string: badge.label.uppercased(),
            attributes: [.font: Self.font, .foregroundColor: Self.ink, .kern: 0.5]
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
            base = CGPoint(x: rect.minX + min(8, rect.width / 2), y: baseY)
            tip = CGPoint(x: base.x, y: baseY + reach)
            across = CGPoint(x: halfBase, y: 0)
            tuck = CGPoint(x: 0, y: badge.caret == .downward ? -1 : 1)
        case .rightward, .leftward:
            let baseX = badge.caret == .rightward ? rect.maxX : rect.minX
            let reach = badge.caret == .rightward ? HintGeometry.caretHeight : -HintGeometry.caretHeight
            base = CGPoint(x: baseX, y: rect.midY)
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
