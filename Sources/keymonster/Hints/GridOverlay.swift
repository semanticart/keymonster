import AppKit

/// Grid mode's overlay over the frontmost window. It shows one of two things:
/// the initial two-character hint grid (`showHints`), or a positional keyboard
/// grid over the active region (`showGrid`) which becomes a loupe — the
/// region's pixels magnified to fill the window — once zoomed in. Transparent
/// and click-through, like `HintOverlay`.
@MainActor
final class GridOverlay {
    private var window: NSWindow?
    private var view: GridOverlayView?
    private var windowOrigin: CGPoint = .zero
    private var windowBounds: CGRect = .zero

    /// Creates the overlay window over `windowFrame` (AX, top-left origin).
    /// Call once when grid mode activates, then drive it with the `show*` calls.
    func present(windowFrame: CGRect) {
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
        windowBounds = CGRect(origin: .zero, size: cocoaFrame.size)
    }

    /// The initial two-character hint grid (`cells` in AX coordinates). `typed`
    /// dims the labels that no longer match what's been entered.
    func showHints(cells: [GridHints.Cell], typed: String) {
        view?.showHints(
            cells: cells.map {
                GridOverlayView.HintCell(label: $0.label, rect: inView($0.rect))
            },
            typed: typed
        )
    }

    /// The positional grid over `current` (AX coordinates), drawn plainly while
    /// it's the whole window and as a magnified loupe once zoomed in. Falls back
    /// to the plain grid when there's nothing to magnify or Screen Recording is
    /// off.
    func showGrid(current: CGRect) {
        let region = inView(current)
        if GridZoom.scale(magnifying: region, into: windowBounds) > 1,
           let image = WindowCapture.below(window, bounds: current) {
            let panel = GridZoom.panel(magnifying: region, into: windowBounds)
            view?.showGrid(region: region, panel: panel, image: image)
        } else {
            view?.showGrid(region: region, panel: region, image: nil)
        }
    }

    /// AX rect to view coordinates. The view is flipped, so it shares the AX
    /// tree's top-left origin — only the window's origin needs removing.
    private func inView(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -windowOrigin.x, dy: -windowOrigin.y)
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        view = nil
    }
}

/// Draws grid mode's overlay: the labelled hint grid, or the positional grid /
/// loupe. Flipped so its coordinates match AX frames.
final class GridOverlayView: NSView {
    struct HintCell {
        let label: String
        let rect: CGRect
    }

    private enum Content {
        /// The positional grid. `region` (view coordinates) names the cells;
        /// `panel` is where they draw — equal to `region` for the plain grid,
        /// or a magnified rect when `image` (the region's screenshot) is set.
        case grid(region: CGRect, panel: CGRect, image: CGImage?)
        /// The initial hint grid; `typed` is the prefix entered so far.
        case hints(cells: [HintCell], typed: String)
    }

    private var content: Content? {
        didSet { needsDisplay = true }
    }

    func showGrid(region: CGRect, panel: CGRect, image: CGImage?) {
        content = .grid(region: region, panel: panel, image: image)
    }

    func showHints(cells: [HintCell], typed: String) {
        content = .hints(cells: cells, typed: typed)
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
    private static let hintFill = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.35, alpha: 0.95)
    private static let hintDimFill = NSColor(calibratedWhite: 0.55, alpha: 0.25)
    private static let hintDimInk = NSColor(calibratedWhite: 0.0, alpha: 0.4)

    override func draw(_ dirtyRect: NSRect) {
        switch content {
        case let .grid(region, panel, image):
            drawGrid(region: region, panel: panel, image: image)
        case let .hints(cells, typed):
            drawHints(cells: cells, typed: typed)
        case nil:
            break
        }
    }

    // MARK: Positional grid / loupe

    private func drawGrid(region: CGRect, panel rawPanel: CGRect, image: CGImage?) {
        let panel = rawPanel.intersection(bounds)
        guard !panel.isEmpty else { return }

        // Dim everything outside the panel.
        let scrim = NSBezierPath(rect: bounds)
        scrim.appendRect(panel)
        scrim.windingRule = .evenOdd
        Self.scrim.setFill()
        scrim.fill()

        // The magnified screenshot of the region, when there is one, clipped to
        // the panel so it can't spill over the dimmed surround.
        if let image {
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: panel).addClip()
            NSImage(cgImage: image, size: .zero).draw(
                in: rawPanel, from: .zero, operation: .sourceOver, fraction: 1,
                respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue]
            )
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        // Cells come from the real region so their keys match what a press
        // selects, then map into the panel for drawing.
        let cells = GridDivision.cells(of: region).map {
            GridDivision.Cell(key: $0.key, rect: mapped($0.rect, from: region, to: rawPanel))
        }
        // Enter clicks the region's center, which maps to the panel's center;
        // once magnified, mark that spot so you can see where a Return lands.
        let target = image != nil ? CGPoint(x: panel.midX, y: panel.midY) : nil
        // Lighter washes over a screenshot so the content stays legible.
        drawCells(cells, in: panel, washAlpha: image == nil ? 0.28 : 0.16)
        drawLabels(of: cells, in: panel, clearing: target)
        if let target { drawTarget(at: target) }
    }

    private static let targetRadius: CGFloat = 4
    private static let targetFill = NSColor(calibratedRed: 1.0, green: 0.24, blue: 0.24, alpha: 0.95)
    private static let targetRing = NSColor(calibratedWhite: 1.0, alpha: 0.95)

    /// A small ringed dot on the spot a Return would click.
    private func drawTarget(at center: CGPoint) {
        let radius = Self.targetRadius
        let dot = NSBezierPath(ovalIn: CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
        ))
        Self.targetFill.setFill()
        dot.fill()
        Self.targetRing.setStroke()
        dot.lineWidth = 1.5
        dot.stroke()
    }

    /// Lifts a badge centered at `center` to sit just above the target dot when
    /// the two would overlap — the dot marks the click point exactly, so a
    /// label under it (the middle cell, when a band or column count is odd)
    /// would otherwise be hidden. Badges the dot doesn't touch stay put.
    private func clearing(_ center: CGPoint, badge: CGSize, dot: CGPoint?) -> CGPoint {
        guard let dot,
              abs(center.x - dot.x) < badge.width / 2 + Self.targetRadius,
              abs(center.y - dot.y) < badge.height / 2 + Self.targetRadius
        else { return center }
        // The view is flipped, so a smaller y sits higher: park the badge's
        // bottom edge just above the dot.
        return CGPoint(x: center.x, y: dot.y - Self.targetRadius - 2 - badge.height / 2)
    }

    /// Maps a cell rect from the real region into the (possibly magnified)
    /// panel. Identity when the two are the same rect (the plain grid).
    private func mapped(_ rect: CGRect, from region: CGRect, to panel: CGRect) -> CGRect {
        guard region.width > 0, region.height > 0 else { return rect }
        let scaleX = panel.width / region.width
        let scaleY = panel.height / region.height
        return CGRect(
            x: panel.minX + (rect.minX - region.minX) * scaleX,
            y: panel.minY + (rect.minY - region.minY) * scaleY,
            width: rect.width * scaleX, height: rect.height * scaleY
        )
    }

    /// A distinct translucent wash per cell so keys read as separate targets,
    /// the cell boundaries, then a stronger border around the region itself.
    private func drawCells(_ cells: [GridDivision.Cell], in panel: CGRect, washAlpha: CGFloat) {
        for cell in cells {
            Self.color(for: cell.key).withAlphaComponent(washAlpha).setFill()
            NSBezierPath(rect: cell.rect).fill()
        }

        let lines = NSBezierPath()
        lines.lineWidth = 1
        for cell in cells.dropFirst() {
            if cell.rect.minX > panel.minX {
                lines.move(to: CGPoint(x: cell.rect.minX, y: cell.rect.minY))
                lines.line(to: CGPoint(x: cell.rect.minX, y: cell.rect.maxY))
            }
            if cell.rect.minY > panel.minY {
                lines.move(to: CGPoint(x: cell.rect.minX, y: cell.rect.minY))
                lines.line(to: CGPoint(x: cell.rect.maxX, y: cell.rect.minY))
            }
        }
        Self.gridLine.setStroke()
        lines.stroke()

        let border = NSBezierPath(rect: panel)
        border.lineWidth = 2
        Self.border.setStroke()
        border.stroke()
    }

    /// Labels stay at a readable size rather than shrinking into the tiny cells
    /// of a zoomed-in grid; when one won't fit inside its cell it's drawn beside
    /// it instead. Besides go in a second pass so they layer on top of the cells
    /// they spill over.
    private func drawLabels(of cells: [GridDivision.Cell], in region: CGRect, clearing target: CGPoint?) {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        var deferred: [GridDivision.Cell] = []
        for cell in cells {
            let badge = badgeSize(of: String(cell.key), font: font)
            if badge.width <= cell.rect.width && badge.height <= cell.rect.height {
                let fill = Self.color(for: cell.key).withAlphaComponent(0.95)
                let center = clearing(
                    CGPoint(x: cell.rect.midX, y: cell.rect.midY), badge: badge, dot: target
                )
                drawBadge(text: String(cell.key), at: center, font: font, fill: fill, ink: Self.ink)
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
            let badge = badgeSize(of: String(cell.key), font: font)
            let columns = max(1, columnsPerBand[cell.rect.minY] ?? 1)
            let column = min(Self.column(of: cell.key), columns - 1)
            let centerX = columns == 1
                ? region.midX
                : region.minX - badge.width / 2 + (region.width + badge.width) * CGFloat(column) / CGFloat(columns - 1)
            let fill = Self.color(for: cell.key).withAlphaComponent(0.95)
            let center = clearing(
                CGPoint(x: centerX, y: cell.rect.midY), badge: badge, dot: target
            )
            drawBadge(text: String(cell.key), at: center, font: font, fill: fill, ink: Self.ink)
        }
    }

    /// A key's column index in its keyboard row, or 0 if it isn't found.
    private static func column(of key: Character) -> Int {
        for keys in GridDivision.rows {
            if let column = keys.firstIndex(of: key) { return column }
        }
        return 0
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

    // MARK: Hint grid

    private func drawHints(cells: [HintCell], typed: String) {
        // The same translucent per-cell washes as the positional grid, so the
        // initial cells read as distinct tiles. Colors step by grid position
        // (rows and columns recovered from the shared cell edges) so no two
        // neighbors match.
        let rowOf = index(of: cells.map(\.rect.minY))
        let columnOf = index(of: cells.map(\.rect.minX))
        for cell in cells {
            let step = (rowOf[cell.rect.minY] ?? 0) * 7 + (columnOf[cell.rect.minX] ?? 0) * 3
            Self.cellColors[step % Self.cellColors.count].setFill()
            NSBezierPath(rect: cell.rect).fill()
        }

        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        let prefix = typed.uppercased()
        func matches(_ cell: HintCell) -> Bool { cell.label.uppercased().hasPrefix(prefix) }

        // Dimmed non-matches first, then live labels on top of them.
        for cell in cells where !matches(cell) {
            drawBadge(
                text: cell.label, at: CGPoint(x: cell.rect.midX, y: cell.rect.midY),
                font: font, fill: Self.hintDimFill, ink: Self.hintDimInk
            )
        }
        for cell in cells where matches(cell) {
            drawBadge(
                text: cell.label, at: CGPoint(x: cell.rect.midX, y: cell.rect.midY),
                font: font, fill: Self.hintFill, ink: Self.ink
            )
        }
    }

    /// Maps each distinct coordinate to its rank, so a cell's shared row/column
    /// edge becomes a 0-based index for coloring.
    private func index(of coordinates: [CGFloat]) -> [CGFloat: Int] {
        Dictionary(uniqueKeysWithValues: Set(coordinates).sorted().enumerated().map { ($1, $0) })
    }

    // MARK: Badges

    /// The size a badge for `text` occupies at `font`.
    private func badgeSize(of text: String, font: NSFont) -> CGSize {
        let attributed = NSAttributedString(string: text.uppercased(), attributes: [.font: font])
        let textSize = attributed.size()
        return CGSize(
            width: textSize.width + font.pointSize * 0.4 * 2,
            height: textSize.height + font.pointSize * 0.17 * 2
        )
    }

    private func drawBadge(text: String, at center: CGPoint, font: NSFont, fill: NSColor, ink: NSColor) {
        let attributed = NSAttributedString(
            string: text.uppercased(),
            attributes: [.font: font, .foregroundColor: ink]
        )
        let textSize = attributed.size()
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
        attributed.draw(at: CGPoint(x: badge.minX + padding.width, y: badge.minY + padding.height))
    }
}
