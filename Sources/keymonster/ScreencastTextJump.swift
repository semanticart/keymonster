import SwiftUI
import AppKit

/// The demo window's markdown-editor pane and the text-jump scene played over
/// it. The pane renders monospaced lines from a fixed layout table so every
/// character has a computable rect — which is what lets the scene hang real
/// hint badges over each occurrence of the jumped-to character, the way
/// `AXFocusedText` finds occurrence rects in a live field.
@MainActor
enum DemoEditorLayout {
    static let lines = [
        "# launch notes",
        "",
        "The monster now lives in the menu bar.",
        "It remembers everything you copy and",
        "hands it back the moment you ask.",
        "",
        "Still to do: teach more people to move",
        "around their Mac without a mouse."
    ]

    static let origin = CGPoint(x: 232, y: 96)
    static let lineHeight: CGFloat = 30
    static let fontSize: CGFloat = 13

    /// One monospaced advance, measured from the same font the pane renders
    /// with, so character columns and badge positions agree.
    static let advance: CGFloat = NSAttributedString(
        string: "0",
        attributes: [.font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)]
    ).size().width

    /// The rect of the character at (line, column), in window coordinates.
    static func characterRect(line: Int, column: Int) -> CGRect {
        CGRect(
            x: origin.x + CGFloat(column) * advance,
            y: origin.y + CGFloat(line) * lineHeight,
            width: advance, height: lineHeight
        )
    }

    /// Every (line, column) whose character matches `character`, reading order,
    /// case-insensitively — like the live occurrence search.
    static func occurrences(of character: Character) -> [(line: Int, column: Int)] {
        let wanted = Character(character.lowercased())
        return lines.enumerated().flatMap { line, text in
            text.enumerated().compactMap { column, char in
                Character(char.lowercased()) == wanted ? (line, column) : nil
            }
        }
    }
}

extension DemoWindow {
    /// The editor pane the text-jump scene types through: monospaced draft
    /// text with a visible caret at `model.caret`. Every character is placed
    /// individually at its `characterRect` so the scene's occurrence badges are
    /// pixel-aligned with the glyphs they label, whatever advance the text
    /// engine would have used.
    var editorPane: some View {
        let textColor = Color.white.opacity(0.86)
        let faintColor = Color.white.opacity(0.42)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(DemoEditorLayout.lines.enumerated()), id: \.offset) { index, line in
                let color = line.hasPrefix("#") ? faintColor : textColor
                ForEach(Array(line.enumerated()), id: \.offset) { column, char in
                    let rect = DemoEditorLayout.characterRect(line: index, column: column)
                    Text(String(char))
                        .font(.system(size: DemoEditorLayout.fontSize, design: .monospaced))
                        .foregroundStyle(color)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            if let caret = model.caret {
                let rect = DemoEditorLayout.characterRect(line: caret.line, column: caret.column)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(red: 0.35, green: 0.66, blue: 0.95))
                    .frame(width: 2, height: 17)
                    .position(x: rect.minX, y: rect.midY)
            }
        }
    }
}

extension ScreencastRunner {
    /// Text jump over the editor: the armed "Jump to a character…" banner, then
    /// pressing "m" grows a label on every visible occurrence, and typing one
    /// drops the caret right before the "m" of "mouse".
    static func textJumpScene(recorder: Recorder, window: NSWindow) {
        let demo = DemoWindowModel()
        demo.editorMode = true
        let lastLine = DemoEditorLayout.lines.count - 1
        demo.caret = (lastLine, DemoEditorLayout.lines[lastLine].count)

        let overlay = HintOverlayModel()
        let state = CastState(caption: "⌃⇧J — jump the caret to any character you can see")
        show(CastCanvas(state: state, panelSize: DemoWindowLayout.overlaySize,
                        content: DemoOverlayScene(model: demo,
                                                  overlay: HintOverlayHost(model: overlay))),
             in: window)
        SnapshotRunner.settle(0.4)

        recorder.fade(state, to: 1, over: 0.3)
        recorder.hold(0.6)

        overlay.banner = "Jump to a character…"
        recorder.hold(0.9)

        // Press "m": the banner gives way to a label on every occurrence.
        overlay.banner = nil
        let hits = DemoEditorLayout.occurrences(of: "m")
        let labels = HintLabels.labels(count: hits.count)
        overlay.badges = zip(hits, labels).map { hit, label in occurrenceBadge(hit, label) }
        recorder.hold(1.5)

        // Jump to the "m" of "mouse": its single-letter label commits at once.
        guard let target = hits.last, let label = labels.last else {
            SnapshotRunner.fail("no text-jump occurrences in the editor text")
        }
        overlay.typed = label
        recorder.hold(0.15)
        overlay.badges = []
        overlay.typed = ""
        demo.caret = target
        recorder.hold(1.0)

        recorder.fade(state, to: 0, over: 0.3)
    }

    /// A hint badge floated just above one character occurrence, caret aimed
    /// down at it.
    private static func occurrenceBadge(
        _ hit: (line: Int, column: Int), _ label: String
    ) -> HintOverlayView.Badge {
        let margin = DemoWindowLayout.overlayMargin
        let size = BadgeMetrics.size(forLabelLength: label.count)
        let char = DemoEditorLayout.characterRect(line: hit.line, column: hit.column)
            .offsetBy(dx: margin, dy: margin)
        let badge = CGRect(
            x: char.midX - size.width / 2,
            y: char.minY - size.height - 3,
            width: size.width, height: size.height
        )
        return HintOverlayView.Badge(
            rect: badge, label: label, area: nil,
            caret: HintOverlayView.caretDirection(from: badge, toward: char)
        )
    }
}
