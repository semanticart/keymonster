import AppKit

/// Highlights grid mode's active region over the frontmost window: everything
/// outside the region is dimmed, and the region is split into eight labeled
/// home-row cells. Transparent and click-through, like `HintOverlay`.
@MainActor
final class GridOverlay {
    private var window: NSWindow?
    private var view: GridOverlayView?
    private var windowOrigin: CGPoint = .zero

    /// `windowFrame` is the target window's frame in AX (top-left origin)
    /// coordinates; `current` is the active region in the same space.
    func show(windowFrame: CGRect, current: CGRect) {
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

        let view = GridOverlayView(frame: CGRect(origin: .zero, size: cocoaFrame.size))
        window.contentView = view
        window.orderFrontRegardless()

        self.window = window
        self.view = view
        windowOrigin = windowFrame.origin
        update(current: current)
    }

    func update(current: CGRect) {
        // The view is flipped, so it shares the AX tree's top-left origin —
        // only the window's origin needs removing.
        view?.current = current.offsetBy(dx: -windowOrigin.x, dy: -windowOrigin.y)
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        view = nil
    }
}

/// Draws the dimmed surroundings, the active region's grid lines, and a key
/// badge at the center of each cell. Flipped so its coordinates match AX frames.
final class GridOverlayView: NSView {
    var current: CGRect = .zero {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    private static let scrim = NSColor.black.withAlphaComponent(0.3)
    private static let gridLine = NSColor(calibratedRed: 1.0, green: 0.87, blue: 0.4, alpha: 0.7)
    private static let border = NSColor(calibratedRed: 1.0, green: 0.87, blue: 0.4, alpha: 0.95)
    private static let badgeFill = NSColor(calibratedRed: 1.0, green: 0.87, blue: 0.4, alpha: 0.95)
    private static let badgeStroke = NSColor(calibratedRed: 0.5, green: 0.38, blue: 0.05, alpha: 0.9)
    private static let ink = NSColor.black

    override func draw(_ dirtyRect: NSRect) {
        let region = current.intersection(bounds)
        guard !region.isEmpty else { return }

        // Dim everything outside the active region.
        let scrim = NSBezierPath(rect: bounds)
        scrim.appendRect(region)
        scrim.windingRule = .evenOdd
        Self.scrim.setFill()
        scrim.fill()

        let cells = GridDivision.cells(of: region)

        // Cell boundaries, then a stronger border around the region itself.
        let lines = NSBezierPath()
        lines.lineWidth = 1
        for cell in cells.dropFirst() {
            if cell.rect.minX > region.minX {
                lines.move(to: CGPoint(x: cell.rect.minX, y: cell.rect.minY))
                lines.line(to: CGPoint(x: cell.rect.minX, y: cell.rect.maxY))
            }
            if cell.rect.minY > region.minY {
                lines.move(to: CGPoint(x: cell.rect.minX, y: cell.rect.minY))
                lines.line(to: CGPoint(x: cell.rect.maxX, y: cell.rect.minY))
            }
        }
        Self.gridLine.setStroke()
        lines.stroke()

        let border = NSBezierPath(rect: region)
        border.lineWidth = 2
        Self.border.setStroke()
        border.stroke()

        // Badges shrink with the cells so a zoomed-in grid stays readable
        // instead of drowning in overlapping labels.
        let minDimension = cells.map { min($0.rect.width, $0.rect.height) }.min() ?? 0
        let fontSize = max(6, min(12, minDimension * 0.6))
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
        for cell in cells {
            drawBadge(key: cell.key, at: CGPoint(x: cell.rect.midX, y: cell.rect.midY), font: font)
        }
    }

    private func drawBadge(key: Character, at center: CGPoint, font: NSFont) {
        let text = NSAttributedString(
            string: String(key).uppercased(),
            attributes: [.font: font, .foregroundColor: Self.ink]
        )
        let textSize = text.size()
        let padding = CGSize(width: font.pointSize * 0.4, height: font.pointSize * 0.17)
        let badge = CGRect(
            x: center.x - textSize.width / 2 - padding.width,
            y: center.y - textSize.height / 2 - padding.height,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )

        let path = NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4)
        Self.badgeFill.setFill()
        path.fill()
        Self.badgeStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
        text.draw(at: CGPoint(x: badge.minX + padding.width, y: badge.minY + padding.height))
    }
}
