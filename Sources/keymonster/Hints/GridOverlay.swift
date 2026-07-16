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

    /// Eight translucent hues, one per cell. Indexed by keyboard position so
    /// no two adjacent cells — sideways, up/down, or diagonally — ever share a
    /// color; the region underneath still shows through.
    private static let cellColors: [NSColor] = (0..<8).map { step in
        NSColor(calibratedHue: CGFloat(step) / 8, saturation: 0.85, brightness: 1.0, alpha: 0.28)
    }

    private static let gridLine = NSColor(calibratedRed: 1.0, green: 0.87, blue: 0.4, alpha: 0.7)
    private static let border = NSColor(calibratedRed: 1.0, green: 0.87, blue: 0.4, alpha: 0.95)
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

        // A distinct translucent wash per cell, so keys read as separate
        // targets before the grid lines and badges go on top.
        for cell in cells {
            Self.color(for: cell.key).setFill()
            NSBezierPath(rect: cell.rect).fill()
        }

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

        drawLabels(of: cells, in: region)
    }

    /// Labels stay at a readable size rather than shrinking into the tiny cells
    /// of a zoomed-in grid; when one won't fit inside its cell it's drawn beside
    /// it instead. Besides go in a second pass so they layer on top of the cells
    /// they spill over.
    private func drawLabels(of cells: [GridDivision.Cell], in region: CGRect) {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        var deferred: [GridDivision.Cell] = []
        for cell in cells {
            let badge = badgeRect(for: cell.key, font: font)
            if badge.width <= cell.rect.width && badge.height <= cell.rect.height {
                let fill = Self.color(for: cell.key).withAlphaComponent(0.95)
                drawBadge(key: cell.key, at: CGPoint(x: cell.rect.midX, y: cell.rect.midY), font: font, fill: fill)
            } else {
                deferred.append(cell)
            }
        }
        // Spread a band's side labels across its width rather than stacking
        // them: the leftmost sits just outside the region's left edge, the
        // rightmost just outside the right, the rest evenly between. They stay
        // on the band's midline — no overlap, so no vertical stagger needed.
        let columnsPerBand = Dictionary(grouping: cells, by: { $0.rect.minY }).mapValues { $0.count }
        for cell in deferred {
            let badge = badgeRect(for: cell.key, font: font)
            let columns = max(1, columnsPerBand[cell.rect.minY] ?? 1)
            let column = min(Self.column(of: cell.key), columns - 1)
            let centerX = columns == 1
                ? region.midX
                : region.minX - badge.width / 2 + (region.width + badge.width) * CGFloat(column) / CGFloat(columns - 1)
            let fill = Self.color(for: cell.key).withAlphaComponent(0.95)
            drawBadge(key: cell.key, at: CGPoint(x: centerX, y: cell.rect.midY), font: font, fill: fill)
        }
    }

    /// A key's column index in its keyboard row, or 0 if it isn't found.
    private static func column(of key: Character) -> Int {
        for keys in GridDivision.rows {
            if let column = keys.firstIndex(of: key) { return column }
        }
        return 0
    }

    /// The size a `key`'s badge occupies at `font`, centered on the origin.
    private func badgeRect(for key: Character, font: NSFont) -> CGSize {
        let text = NSAttributedString(string: String(key).uppercased(), attributes: [.font: font])
        let textSize = text.size()
        return CGSize(
            width: textSize.width + font.pointSize * 0.4 * 2,
            height: textSize.height + font.pointSize * 0.17 * 2
        )
    }

    /// The wash for a cell, chosen from its (row, column) on the keyboard.
    /// Stepping 7 per row and 3 per column keeps every orthogonal and diagonal
    /// neighbor a different index modulo the eight-color palette.
    private static func color(for key: Character) -> NSColor {
        for (row, keys) in GridDivision.rows.enumerated() {
            if let column = keys.firstIndex(of: key) {
                return cellColors[(row * 7 + column * 3) % cellColors.count]
            }
        }
        return cellColors[0]
    }

    private func drawBadge(key: Character, at center: CGPoint, font: NSFont, fill: NSColor) {
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
        fill.setFill()
        path.fill()
        Self.badgeStroke.setStroke()
        path.lineWidth = 1
        path.stroke()
        text.draw(at: CGPoint(x: badge.minX + padding.width, y: badge.minY + padding.height))
    }
}
