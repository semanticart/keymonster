import AppKit

/// The monochrome menu-bar glyph: a paperclip with a small open "eye" ring at
/// the head — the template-image echo of the app icon (`Resources/icon.svg`).
///
/// Coordinates are taken from that SVG's 1024×1024 design space, converted to
/// AppKit's y-up orientation (yUp = 1024 - ySVG). Returned as a template image
/// so macOS tints it for light/dark menu bars.
enum MenuBarIcon {
    static func image(height: CGFloat = 18) -> NSImage {
        let body = NSBezierPath()
        body.lineCapStyle = .round
        body.lineJoinStyle = .round
        body.lineWidth = 46
        body.move(to: CGPoint(x: 380, y: 702))
        body.line(to: CGPoint(x: 380, y: 304))
        body.appendArc(withCenter: CGPoint(x: 530, y: 304), radius: 150,
                       startAngle: 180, endAngle: 360, clockwise: false)
        body.line(to: CGPoint(x: 680, y: 664))
        body.appendArc(withCenter: CGPoint(x: 605, y: 664), radius: 75,
                       startAngle: 0, endAngle: 180, clockwise: false)
        body.line(to: CGPoint(x: 530, y: 364))

        // Open "eye" ring centered at (380, 772), radius 70.
        let ring = NSBezierPath(ovalIn: CGRect(x: 310, y: 702, width: 140, height: 140))
        ring.lineWidth = 34

        // Tight bounding box of the strokes above, used to fit the glyph to height.
        let box = CGRect(x: 293, y: 131, width: 410, height: 728)
        let scale = height / box.height
        let size = NSSize(width: box.width * scale, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            NSColor.black.setStroke()
            body.stroke()
            ring.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
