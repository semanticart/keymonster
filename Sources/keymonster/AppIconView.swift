import SwiftUI

/// The full-color app icon — the Key Monster chomping a keyboard — drawn from
/// the same geometry as `Resources/icon.svg` (a 1024×1024 design space).
/// Rendering it in code lets us show the app's identity crisply at any size
/// in-app without loading the bundled `.icns`, so it also works in the
/// headless snapshot tool.
struct AppIconView: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 1024, y: size.height / 1024)
            Self.drawFace(&ctx)

            var inner = ctx
            inner.clip(to: Self.squircle)
            Self.drawMouth(&inner)
            Self.drawKeyboard(&inner)
            Self.drawLipAndCrumbs(&inner)
            Self.drawFlyingKeycaps(&inner)

            Self.drawEyes(&ctx)
        }
    }

    private static let squircle = Path(
        roundedRect: CGRect(x: 92, y: 92, width: 840, height: 840),
        cornerRadius: 196, style: .continuous)

    /// Blue fur fills the whole squircle, with a soft top-left sheen and a
    /// jagged darker fringe of fur across the brow.
    private static func drawFace(_ ctx: inout GraphicsContext) {
        ctx.fill(squircle, with: .linearGradient(
            Gradient(colors: [Color(rgb: 0x45b3f0), Color(rgb: 0x1868b6)]),
            startPoint: CGPoint(x: 512, y: 92), endPoint: CGPoint(x: 512, y: 932)))
        ctx.fill(squircle, with: .radialGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0.25), location: 0),
                .init(color: .white.opacity(0), location: 0.5)
            ]),
            center: CGPoint(x: 386, y: 302), startRadius: 0, endRadius: 756))

        var fringe = Path()
        fringe.move(to: CGPoint(x: 92, y: 250))
        let tufts: [CGPoint] = [
            .init(x: 170, y: 205), .init(x: 225, y: 258), .init(x: 290, y: 200),
            .init(x: 350, y: 252), .init(x: 415, y: 198), .init(x: 480, y: 250),
            .init(x: 545, y: 196), .init(x: 610, y: 248), .init(x: 675, y: 194),
            .init(x: 740, y: 246), .init(x: 805, y: 198), .init(x: 870, y: 250),
            .init(x: 932, y: 205)
        ]
        for point in tufts { fringe.addLine(to: point) }
        fringe.addLine(to: CGPoint(x: 932, y: 92))
        fringe.addLine(to: CGPoint(x: 92, y: 92))
        fringe.closeSubpath()

        var clipped = ctx
        clipped.clip(to: squircle)
        clipped.fill(fringe, with: .color(Color(rgb: 0x1a72c4).opacity(0.55)))
    }

    private static func drawMouth(_ ctx: inout GraphicsContext) {
        var mouth = Path()
        mouth.move(to: CGPoint(x: 150, y: 610))
        mouth.addCurve(to: CGPoint(x: 874, y: 610),
                       control1: CGPoint(x: 320, y: 520), control2: CGPoint(x: 704, y: 520))
        mouth.addCurve(to: CGPoint(x: 512, y: 940),
                       control1: CGPoint(x: 874, y: 810), control2: CGPoint(x: 730, y: 940))
        mouth.addCurve(to: CGPoint(x: 150, y: 610),
                       control1: CGPoint(x: 294, y: 940), control2: CGPoint(x: 150, y: 810))
        mouth.closeSubpath()
        ctx.fill(mouth, with: .color(Color(rgb: 0x131c26)))

        var shadow = Path()
        shadow.move(to: CGPoint(x: 200, y: 640))
        shadow.addCurve(to: CGPoint(x: 824, y: 640),
                        control1: CGPoint(x: 340, y: 580), control2: CGPoint(x: 684, y: 580))
        shadow.addCurve(to: CGPoint(x: 512, y: 740),
                        control1: CGPoint(x: 810, y: 700), control2: CGPoint(x: 760, y: 740))
        shadow.addCurve(to: CGPoint(x: 200, y: 640),
                        control1: CGPoint(x: 264, y: 740), control2: CGPoint(x: 214, y: 700))
        shadow.closeSubpath()
        ctx.fill(shadow, with: .color(Color(rgb: 0x0a1118)))
    }

    /// The chomped keyboard: tilted, lower edge in the mouth, with the
    /// top-right corner bitten clean off (the bite clips through the keys).
    private static func drawKeyboard(_ ctx: inout GraphicsContext) {
        var board = ctx
        board.translateBy(x: 512, y: 690)
        board.rotate(by: .degrees(-10))
        board.translateBy(x: -512, y: -690)

        var bite = Path(CGRect(x: -512, y: -512, width: 2048, height: 2048))
        bite.addEllipse(in: circleRect(x: 712, y: 560, radius: 62))
        bite.addEllipse(in: circleRect(x: 646, y: 536, radius: 46))
        bite.addEllipse(in: circleRect(x: 740, y: 646, radius: 52))
        board.clip(to: bite, style: FillStyle(eoFill: true))

        let body = Path(roundedRect: CGRect(x: 300, y: 545, width: 424, height: 270),
                        cornerRadius: 28)
        board.fill(body, with: .linearGradient(
            Gradient(colors: [Color(rgb: 0xf4f7f9), Color(rgb: 0xcfd9df)]),
            startPoint: CGPoint(x: 512, y: 545), endPoint: CGPoint(x: 512, y: 815)))
        board.stroke(body, with: .color(Color(rgb: 0x93a5b1)), lineWidth: 6)

        var keys = Path()
        for row in 0..<3 {
            for col in 0..<7 {
                keys.addRoundedRect(
                    in: CGRect(x: 326 + col * 52, y: 572 + row * 52, width: 44, height: 44),
                    cornerSize: CGSize(width: 10, height: 10))
            }
        }
        for keyX in [326, 378, 610, 662] {
            keys.addRoundedRect(in: CGRect(x: keyX, y: 728, width: 44, height: 44),
                                cornerSize: CGSize(width: 10, height: 10))
        }
        keys.addRoundedRect(in: CGRect(x: 430, y: 728, width: 172, height: 44),
                            cornerSize: CGSize(width: 10, height: 10))
        board.fill(keys, with: .color(.white))
        board.stroke(keys, with: .color(Color(rgb: 0xaebcc6)), lineWidth: 4)
    }

    /// The lower lip laps over the keyboard so it sits *in* the mouth, plus a
    /// few white crumb flecks.
    private static func drawLipAndCrumbs(_ ctx: inout GraphicsContext) {
        var lip = Path()
        lip.move(to: CGPoint(x: 150, y: 800))
        lip.addCurve(to: CGPoint(x: 512, y: 830),
                     control1: CGPoint(x: 250, y: 760), control2: CGPoint(x: 380, y: 830))
        lip.addCurve(to: CGPoint(x: 874, y: 800),
                     control1: CGPoint(x: 644, y: 830), control2: CGPoint(x: 774, y: 760))
        lip.addCurve(to: CGPoint(x: 512, y: 950),
                     control1: CGPoint(x: 830, y: 900), control2: CGPoint(x: 700, y: 950))
        lip.addCurve(to: CGPoint(x: 150, y: 800),
                     control1: CGPoint(x: 324, y: 950), control2: CGPoint(x: 194, y: 900))
        lip.closeSubpath()
        ctx.fill(lip, with: .color(Color(rgb: 0x1f7ccb)))

        var crumbs = Path()
        crumbs.addEllipse(in: circleRect(x: 300, y: 560, radius: 14))
        crumbs.addEllipse(in: circleRect(x: 262, y: 512, radius: 9))
        crumbs.addEllipse(in: circleRect(x: 340, y: 500, radius: 7))
        ctx.fill(crumbs, with: .color(Color(rgb: 0xe8eef2)))
    }

    /// Bitten-off keycaps flying like crumbs; the big one wears a ⌘.
    private static func drawFlyingKeycaps(_ ctx: inout GraphicsContext) {
        drawKeycap(&ctx, rect: CGRect(x: 786, y: 444, width: 52, height: 52),
                   cornerRadius: 12, degrees: 24)
        var command = ctx
        command.translateBy(x: 812, y: 470)
        command.rotate(by: .degrees(24))
        command.translateBy(x: -812, y: -470)
        var glyph = Path()
        glyph.move(to: CGPoint(x: 802, y: 460)); glyph.addLine(to: CGPoint(x: 822, y: 460))
        glyph.move(to: CGPoint(x: 802, y: 480)); glyph.addLine(to: CGPoint(x: 822, y: 480))
        glyph.move(to: CGPoint(x: 802, y: 460)); glyph.addLine(to: CGPoint(x: 802, y: 480))
        glyph.move(to: CGPoint(x: 822, y: 460)); glyph.addLine(to: CGPoint(x: 822, y: 480))
        for corner in [CGPoint(x: 802, y: 460), CGPoint(x: 822, y: 460),
                       CGPoint(x: 802, y: 480), CGPoint(x: 822, y: 480)] {
            glyph.addEllipse(in: circleRect(x: corner.x, y: corner.y, radius: 5))
        }
        command.stroke(glyph, with: .color(Color(rgb: 0x7d8f9b)),
                       style: StrokeStyle(lineWidth: 7, lineCap: .round))

        drawKeycap(&ctx, rect: CGRect(x: 742, y: 360, width: 40, height: 40),
                   cornerRadius: 10, degrees: -18)
        drawKeycap(&ctx, rect: CGRect(x: 852, y: 560, width: 34, height: 34),
                   cornerRadius: 9, degrees: 40)
    }

    private static func drawKeycap(_ ctx: inout GraphicsContext, rect: CGRect,
                                   cornerRadius: CGFloat, degrees: Double) {
        var cap = ctx
        cap.translateBy(x: rect.midX, y: rect.midY)
        cap.rotate(by: .degrees(degrees))
        cap.translateBy(x: -rect.midX, y: -rect.midY)
        let path = Path(roundedRect: rect, cornerRadius: cornerRadius)
        cap.fill(path, with: .color(.white))
        cap.stroke(path, with: .color(Color(rgb: 0xaebcc6)), lineWidth: 4)
    }

    /// Wonky googly eyes, drawn unclipped so they can kiss the fringe.
    private static func drawEyes(_ ctx: inout GraphicsContext) {
        for (center, pupil) in [
            (CGPoint(x: 398, y: 330), CGPoint(x: 438, y: 378)),
            (CGPoint(x: 642, y: 296), CGPoint(x: 598, y: 330))
        ] {
            let white = Path(ellipseIn: circleRect(x: center.x, y: center.y, radius: 122))
            ctx.fill(white, with: .color(.white))
            ctx.stroke(white, with: .color(Color(rgb: 0x0e2a44).opacity(0.12)), lineWidth: 8)
            ctx.fill(Path(ellipseIn: circleRect(x: pupil.x, y: pupil.y, radius: 44)),
                     with: .color(Color(rgb: 0x101418)))
        }
    }

    private static func circleRect(x centerX: CGFloat, y centerY: CGFloat,
                                   radius: CGFloat) -> CGRect {
        CGRect(x: centerX - radius, y: centerY - radius,
               width: radius * 2, height: radius * 2)
    }
}

private extension Color {
    /// Builds a Color from a 0xRRGGBB literal, matching the hex colors in `icon.svg`.
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
