import AppKit

/// The monochrome menu-bar glyph: a keyboard with a giant bite taken out of
/// the top-right quadrant — the Key Monster was here. The template-image echo
/// of the app icon (`Resources/icon.svg`).
///
/// Coordinates are taken from that icon's 1024×1024 design space, converted to
/// AppKit's y-up orientation (yUp = 1024 - ySVG). Everything is one even-odd
/// filled path, so the keycaps read as transparent holes. Returned as a
/// template image so macOS tints it for light/dark menu bars.
enum MenuBarIcon {
    /// `badged` adds a small green dot floating in the bite — the
    /// update-available marker. The badged image can't be a template (macOS
    /// would tint the dot monochrome along with the glyph), so it draws the
    /// keyboard in `labelColor` instead; the drawing handler re-runs per
    /// appearance, keeping it legible in light and dark menu bars.
    static func image(height: CGFloat = 18, badged: Bool = false) -> NSImage {
        let path = NSBezierPath()
        path.windingRule = .evenOdd

        // Keyboard outline: rounded rect, but the top-right quadrant is two
        // big bite scallops (r=170) from (500, 792) down to (962, 464).
        path.move(to: CGPoint(x: 126, y: 792))
        path.line(to: CGPoint(x: 500, y: 792))
        path.appendArc(withCenter: CGPoint(x: 670.0, y: 794.0), radius: 170,
                       startAngle: 180.7, endAngle: 298.1, clockwise: false)
        path.appendArc(withCenter: CGPoint(x: 919.3, y: 628.6), radius: 170,
                       startAngle: 174.8, endAngle: 284.5, clockwise: false)
        path.line(to: CGPoint(x: 962, y: 296))
        path.appendArc(withCenter: CGPoint(x: 898, y: 296), radius: 64,
                       startAngle: 0, endAngle: 270, clockwise: true)
        path.line(to: CGPoint(x: 126, y: 232))
        path.appendArc(withCenter: CGPoint(x: 126, y: 296), radius: 64,
                       startAngle: 270, endAngle: 180, clockwise: true)
        path.line(to: CGPoint(x: 62, y: 728))
        path.appendArc(withCenter: CGPoint(x: 126, y: 728), radius: 64,
                       startAngle: 180, endAngle: 90, clockwise: true)
        path.close()

        // Keycap holes (130×130 on a 154 grid); the bite ate the top-right ones.
        for keyX: CGFloat in [139, 293] {
            appendKey(path, x: keyX, y: 602)
        }
        for keyX: CGFloat in [139, 293, 447, 601] {
            appendKey(path, x: keyX, y: 448)
        }
        for keyX: CGFloat in [139, 755] {
            appendKey(path, x: keyX, y: 294)
        }
        appendKey(path, x: 293, y: 294, width: 438) // spacebar

        // Tight bounding box of the shapes above, used to fit the glyph to height.
        let box = CGRect(x: 62, y: 232, width: 900, height: 560)
        let scale = height / box.height
        // Horizontally compress the glyph to 75% of its natural width, keeping
        // the full menu-bar height.
        let widthRatio: CGFloat = 0.75
        let size = NSSize(width: box.width * scale * widthRatio, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.scaleBy(x: scale * widthRatio, y: scale)
            ctx.translateBy(x: -box.minX, y: -box.minY)
            (badged ? NSColor.labelColor : NSColor.black).setFill()
            path.fill()
            if badged {
                // Inside the bite's empty space (both scallop circles cover it)
                // and under the box's top edge, so nothing clips. Drawn wider
                // than tall to cancel the 75% horizontal compression below and
                // come out a circle on screen.
                NSColor.systemGreen.setFill()
                let dot = NSBezierPath(ovalIn: CGRect(x: 775, y: 645, width: 140 / widthRatio, height: 140))
                dot.fill()
            }
            return true
        }
        image.isTemplate = !badged
        return image
    }

    private static func appendKey(_ path: NSBezierPath, x keyX: CGFloat, y keyY: CGFloat,
                                  width: CGFloat = 130) {
        path.appendRoundedRect(CGRect(x: keyX, y: keyY, width: width, height: 130),
                               xRadius: 28, yRadius: 28)
    }
}
