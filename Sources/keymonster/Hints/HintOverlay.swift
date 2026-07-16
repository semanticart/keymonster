import AppKit

/// Shows hint badges in a transparent, click-through window laid exactly over
/// the frontmost app's focused window.
@MainActor
final class HintOverlay {
    private var window: NSWindow?
    private var view: HintOverlayView?

    /// `windowFrame` is the target window's frame in AX (top-left origin)
    /// coordinates — the same space the targets' frames are in.
    func show(targets: [HintTarget], labels: [String], windowFrame: CGRect) {
        hide()
        guard let primary = NSScreen.screens.first else { return }
        let cocoaFrame = HintGeometry.cocoaRect(
            fromAX: windowFrame, primaryScreenHeight: primary.frame.height
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
        // Hint frames become view-local (the view is flipped, so it shares the
        // AX tree's top-left origin — only the window's origin needs removing).
        view.hints = zip(targets, labels).map { target, label in
            HintOverlayView.Hint(
                frame: target.frame.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY),
                label: label
            )
        }
        window.contentView = view
        window.orderFrontRegardless()

        self.window = window
        self.view = view
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

/// Draws a rounded badge with the (remaining part of the) label at the center
/// of each hinted element. Flipped so its coordinates match AX frames.
final class HintOverlayView: NSView {
    struct Hint {
        let frame: CGRect
        let label: String
    }

    var hints: [Hint] = [] {
        didSet { needsDisplay = true }
    }

    /// Letters typed so far; badges not matching this prefix disappear and the
    /// matched prefix renders dimmed on the rest.
    var typed: String = "" {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    private static let fill = NSColor(calibratedRed: 1.0, green: 0.87, blue: 0.4, alpha: 0.95)
    private static let stroke = NSColor(calibratedRed: 0.5, green: 0.38, blue: 0.05, alpha: 0.9)
    private static let ink = NSColor.black
    private static let typedInk = NSColor.black.withAlphaComponent(0.35)

    override func draw(_ dirtyRect: NSRect) {
        for hint in hints where hint.label.hasPrefix(typed) {
            drawBadge(for: hint)
        }
    }

    private func drawBadge(for hint: Hint) {
        let text = NSMutableAttributedString(
            string: hint.label.uppercased(),
            attributes: [.font: Self.font, .foregroundColor: Self.ink, .kern: 0.5]
        )
        if !typed.isEmpty {
            text.addAttribute(
                .foregroundColor, value: Self.typedInk,
                range: NSRange(location: 0, length: typed.count)
            )
        }

        let textSize = text.size()
        let padding = CGSize(width: 5, height: 2)
        var badge = CGRect(
            x: hint.frame.midX - textSize.width / 2 - padding.width,
            y: hint.frame.midY - textSize.height / 2 - padding.height,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )
        // Keep badges legible even when the element pokes past the window edge.
        badge.origin.x = min(max(badge.minX, 0), max(0, bounds.width - badge.width))
        badge.origin.y = min(max(badge.minY, 0), max(0, bounds.height - badge.height))

        let path = NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4)
        Self.fill.setFill()
        path.fill()
        Self.stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
        text.draw(at: CGPoint(x: badge.minX + padding.width, y: badge.minY + padding.height))
    }
}
