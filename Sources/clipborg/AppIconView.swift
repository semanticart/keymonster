import SwiftUI

/// The full-color app icon — the cyborg paperclip — drawn from the same geometry
/// as `Resources/icon.svg` (a 1024×1024 design space). Rendering it in code lets
/// us show the app's identity crisply at any size in-app without loading the
/// bundled `.icns`, so it also works in the headless snapshot tool.
struct AppIconView: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.scaleBy(x: size.width / 1024, y: size.height / 1024)

            // Background squircle.
            let backdrop = Path(roundedRect: CGRect(x: 92, y: 92, width: 840, height: 840),
                                cornerRadius: 196, style: .continuous)
            ctx.fill(backdrop, with: .linearGradient(
                Gradient(colors: [Color(rgb: 0x5a6772), Color(rgb: 0x2f3942)]),
                startPoint: CGPoint(x: 512, y: 92), endPoint: CGPoint(x: 512, y: 932)))

            // Paperclip body.
            var clip = Path()
            clip.move(to: CGPoint(x: 392, y: 300))
            clip.addLine(to: CGPoint(x: 392, y: 700))
            clip.addArc(center: CGPoint(x: 512, y: 700), radius: 120,
                        startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            clip.addLine(to: CGPoint(x: 632, y: 360))
            clip.addArc(center: CGPoint(x: 568, y: 360), radius: 64,
                        startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
            clip.addLine(to: CGPoint(x: 504, y: 660))
            ctx.stroke(clip, with: .linearGradient(
                Gradient(colors: [Color(rgb: 0xffffff), Color(rgb: 0xdfe6ea), Color(rgb: 0xaab6bd)]),
                startPoint: CGPoint(x: 392, y: 296), endPoint: CGPoint(x: 632, y: 820)),
                style: StrokeStyle(lineWidth: 58, lineCap: .round, lineJoin: .round))

            // Cyborg eye at the clip head, centered at (392, 300).
            let glow = Path(ellipseIn: CGRect(x: 276, y: 184, width: 232, height: 232))
            ctx.fill(glow, with: .radialGradient(
                Gradient(colors: [Color(rgb: 0x46ff95).opacity(0.6), Color(rgb: 0x46ff95).opacity(0)]),
                center: CGPoint(x: 392, y: 300), startRadius: 0, endRadius: 116))

            let socket = Path(ellipseIn: CGRect(x: 334, y: 242, width: 116, height: 116))
            ctx.fill(socket, with: .color(Color(rgb: 0x06140c)))

            let lens = Path(ellipseIn: CGRect(x: 348, y: 256, width: 88, height: 88))
            ctx.fill(lens, with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(rgb: 0xd6ffe6), location: 0),
                    .init(color: Color(rgb: 0x34e078), location: 0.4),
                    .init(color: Color(rgb: 0x0b7a3b), location: 1)
                ]),
                center: CGPoint(x: 383.2, y: 286.8), startRadius: 0, endRadius: 66))

            let highlight = Path(ellipseIn: CGRect(x: 366, y: 274, width: 24, height: 24))
            ctx.fill(highlight, with: .color(Color(rgb: 0xeafff2).opacity(0.9)))
        }
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
