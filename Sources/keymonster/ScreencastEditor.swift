#if DEBUG
import SwiftUI
import AppKit

/// The edit-in-editor scene: the demo window's draft is handed to vim in a
/// terminal window that pops up in front, a few keystrokes change a line,
/// `:wq` closes it, and the edited text lands back in the field.
///
/// Unlike the click scenes, nothing here reuses a live component — the
/// feature is process plumbing (a file, an editor, a write-back), not an
/// overlay — so the terminal is a stylised stand-in drawn the way the demo
/// window is, not a screenshot of any real terminal app.
@MainActor
final class DemoTerminalModel: ObservableObject {
    enum Mode {
        case normal, insert, command
    }

    /// 0...1 pop-in progress: the window scales and fades in with it.
    @Published var presence: Double = 0
    @Published var lines: [String] = []
    @Published var cursor = (line: 0, column: 0)
    @Published var mode: Mode = .normal
    /// The `:` command line being typed, in command mode.
    @Published var commandText = ""
    /// What the status line shows in normal mode (vim's "file opened" message).
    @Published var message = ""
}

enum DemoTerminalLayout {
    static let size = CGSize(width: 620, height: 400)
    static let titleBarHeight: CGFloat = 34
    static let lineHeight: CGFloat = 22
    static let inset: CGFloat = 14
    static let rows = 14

    static func lineRect(_ line: Int) -> CGRect {
        CGRect(x: inset, y: titleBarHeight + inset + CGFloat(line) * lineHeight,
               width: size.width - inset * 2, height: lineHeight)
    }

    static var statusRect: CGRect {
        CGRect(x: 0, y: size.height - lineHeight - 6, width: size.width, height: lineHeight + 6)
    }
}

struct DemoTerminal: View {
    @ObservedObject var model: DemoTerminalModel

    private let background = Color(red: 0.055, green: 0.06, blue: 0.075)
    private let chrome = Color.white.opacity(0.07)
    private let border = Color.white.opacity(0.14)
    private let text = Color.white.opacity(0.9)
    private let faint = Color.white.opacity(0.4)
    private let tilde = Color(red: 0.35, green: 0.55, blue: 0.85).opacity(0.6)
    private let cursorColor = Color(red: 0.55, green: 0.85, blue: 0.55)
    private let font = Font.system(size: DemoEditorLayout.fontSize, design: .monospaced)

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(background)
            titleBar
            rows
            cursor
            statusLine
        }
        .frame(width: DemoTerminalLayout.size.width, height: DemoTerminalLayout.size.height)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.6), radius: 30, y: 18)
    }

    private var titleBar: some View {
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
                .fill(chrome)
                .frame(height: DemoTerminalLayout.titleBarHeight)
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 12, height: 12)
            }
            .padding(.leading, 16)
            .frame(height: DemoTerminalLayout.titleBarHeight)
            Text("vim — text.txt")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(faint)
                .frame(width: DemoTerminalLayout.size.width, height: DemoTerminalLayout.titleBarHeight)
        }
    }

    private var rows: some View {
        ForEach(0..<DemoTerminalLayout.rows, id: \.self) { row in
            let rect = DemoTerminalLayout.lineRect(row)
            let isFile = row < model.lines.count
            Text(isFile ? model.lines[row] : "~")
                .font(font)
                .foregroundStyle(isFile ? text : tilde)
                .frame(width: rect.width, height: rect.height, alignment: .leading)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    /// A block cursor in normal mode, a bar while inserting; hidden while the
    /// command line has it.
    @ViewBuilder private var cursor: some View {
        if model.mode != .command {
            let rect = DemoTerminalLayout.lineRect(model.cursor.line)
            let cursorX = rect.minX + CGFloat(model.cursor.column) * DemoEditorLayout.advance
            switch model.mode {
            case .normal:
                let under = model.lines[safe: model.cursor.line]
                    .flatMap { line -> Character? in
                        let index = line.index(line.startIndex, offsetBy: model.cursor.column,
                                               limitedBy: line.endIndex)
                        return index.flatMap { $0 < line.endIndex ? line[$0] : nil }
                    }
                ZStack {
                    Rectangle().fill(cursorColor)
                    if let under {
                        Text(String(under)).font(font).foregroundStyle(background)
                    }
                }
                .frame(width: DemoEditorLayout.advance, height: rect.height - 4)
                .position(x: cursorX + DemoEditorLayout.advance / 2, y: rect.midY)
            case .insert:
                Rectangle().fill(cursorColor)
                    .frame(width: 2, height: rect.height - 4)
                    .position(x: cursorX, y: rect.midY)
            case .command:
                EmptyView()
            }
        }
    }

    private var statusLine: some View {
        let rect = DemoTerminalLayout.statusRect
        let label: String
        switch model.mode {
        case .normal: label = model.message
        case .insert: label = "-- INSERT --"
        case .command: label = ":" + model.commandText
        }
        return ZStack(alignment: .leading) {
            UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12)
                .fill(chrome)
            HStack(spacing: 0) {
                Text(label)
                    .font(font.weight(model.mode == .insert ? .bold : .regular))
                    .foregroundStyle(text)
                if model.mode == .command {
                    Rectangle().fill(cursorColor)
                        .frame(width: DemoEditorLayout.advance, height: rect.height - 10)
                }
            }
            .padding(.leading, DemoTerminalLayout.inset)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// The demo window, dimmed as the terminal comes forward, with the terminal
/// popping in over it.
struct DemoEditorScene: View {
    @ObservedObject var model: DemoWindowModel
    @ObservedObject var terminal: DemoTerminalModel

    var body: some View {
        ZStack {
            DemoWindow(model: model)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.4 * terminal.presence))
                )
            DemoTerminal(model: terminal)
                .scaleEffect(0.92 + 0.08 * terminal.presence)
                .opacity(terminal.presence)
                .offset(x: 40, y: 24)
        }
        .frame(width: DemoWindowLayout.overlaySize.width,
               height: DemoWindowLayout.overlaySize.height)
    }
}

extension ScreencastRunner {
    /// Edit in editor over the draft: the chord pops vim up in front of the
    /// window with the field's text loaded, `G`, `f`, and `cw` rewrite the end
    /// of the last line, `:wq` closes it, and the edit lands back in the field.
    static func editorScene(recorder: Recorder, window: NSWindow) {
        let demo = DemoWindowModel()
        demo.editorMode = true
        let lastLine = demo.editorLines.count - 1
        demo.caret = (lastLine, demo.editorLines[lastLine].count)

        let terminal = DemoTerminalModel()
        let state = CastState(caption: "Edit in Editor — hand any text field to your $EDITOR")
        show(CastCanvas(state: state, panelSize: DemoWindowLayout.overlaySize,
                        content: DemoEditorScene(model: demo, terminal: terminal)),
             in: window)
        SnapshotRunner.settle(0.4)

        recorder.begin("editor")
        recorder.fade(state, to: 1, over: 0.3)
        recorder.hold(0.7)

        // The chord: vim opens on the field's text, in a terminal in front.
        terminal.lines = demo.editorLines
        let bytes = demo.editorLines.joined(separator: "\n").utf8.count + 1
        terminal.message = "\"text.txt\" \(demo.editorLines.count)L, \(bytes)B"
        recorder.animate(over: 0.25) { terminal.presence = $0 }
        recorder.hold(1.0)

        rewriteLastLine(in: terminal, recorder: recorder)

        // :wq
        terminal.mode = .command
        for char in "wq" {
            terminal.commandText.append(char)
            recorder.hold(0.14)
        }
        recorder.hold(0.5)

        // Return: the editor exits 0 and the edited text replaces the field's.
        recorder.animate(over: 0.2) { terminal.presence = 1 - $0 }
        demo.editorLines = terminal.lines
        demo.caret = (lastLine, terminal.lines[lastLine].count)
        demo.highlightedLine = lastLine
        recorder.hold(0.9)
        demo.highlightedLine = nil
        recorder.hold(0.9)

        recorder.end(fading: state)
    }

    /// The edit itself: `G` to the last line, `f` to the "a" of "a mouse",
    /// `cw` to drop the word into insert mode, "touching the" typed in, `Esc`.
    private static func rewriteLastLine(in terminal: DemoTerminalModel, recorder: Recorder) {
        let lastLine = terminal.lines.count - 1
        guard let wordRange = terminal.lines[lastLine].range(of: "a mouse") else {
            SnapshotRunner.fail("the editor text no longer ends in 'a mouse'")
        }
        let column = terminal.lines[lastLine].distance(
            from: terminal.lines[lastLine].startIndex, to: wordRange.lowerBound
        )
        terminal.cursor = (lastLine, 0)
        terminal.message = ""
        recorder.hold(0.45)
        terminal.cursor = (lastLine, column)
        recorder.hold(0.45)

        terminal.lines[lastLine].remove(at: wordRange.lowerBound)
        terminal.mode = .insert
        recorder.hold(0.35)
        for (index, char) in "touching the".enumerated() {
            let line = terminal.lines[lastLine]
            let insertion = line.index(line.startIndex, offsetBy: terminal.cursor.column)
            terminal.lines[lastLine].insert(char, at: insertion)
            terminal.cursor.column += 1
            recorder.hold(index.isMultiple(of: 3) ? 0.15 : 0.1)
        }
        recorder.hold(0.5)

        terminal.mode = .normal
        terminal.cursor.column -= 1
        recorder.hold(0.5)
    }
}
#endif
