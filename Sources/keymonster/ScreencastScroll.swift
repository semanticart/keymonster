#if DEBUG
import SwiftUI
import AppKit

extension DemoWindow {
    /// Everything in the content pane that moves when the scroll scene drives
    /// `contentScroll`: the checklist the other scenes show, plus an "Up next"
    /// section that starts below the fold and only ever appears by scrolling.
    var scrollingCopy: some View {
        let text = Color.white.opacity(0.86)
        return ZStack(alignment: .topLeading) {
            Text("Launch checklist")
                .font(.system(size: 20, weight: .bold)).foregroundStyle(text)
                .position(x: 232 + 82, y: 84)
            ForEach(Array(checklist.enumerated()), id: \.offset) { index, line in
                checklistRow(line).position(x: 232 + 200, y: 132 + CGFloat(index) * 34)
            }
            Text("github.com/semanticart/keymonster")
                .font(.system(size: 13)).underline()
                .foregroundStyle(Color(red: 0.35, green: 0.66, blue: 0.95))
                .frame(width: DemoWindowLayout.link.width,
                       height: DemoWindowLayout.link.height, alignment: .leading)
                .position(x: DemoWindowLayout.link.midX, y: DemoWindowLayout.link.midY)
            Text("Up next")
                .font(.system(size: 20, weight: .bold)).foregroundStyle(text)
                .position(x: 232 + 44, y: 388)
            ForEach(Array(upNext.enumerated()), id: \.offset) { index, line in
                checklistRow(line).position(x: 232 + 200, y: 436 + CGFloat(index) * 34)
            }
        }
    }

    private func checklistRow(_ line: (title: String, done: Bool)) -> some View {
        let accent = Color(red: 0.12, green: 0.49, blue: 0.80)
        let text = Color.white.opacity(0.86)
        let faint = Color.white.opacity(0.42)
        return HStack(spacing: 10) {
            Text(line.done ? "✓" : "▢")
                .font(.system(size: 13)).foregroundStyle(line.done ? accent : faint)
            Text(line.title).font(.system(size: 13)).foregroundStyle(text)
                .strikethrough(line.done, color: faint)
        }
        .frame(width: 400, height: 24, alignment: .leading)
    }

    private var checklist: [(title: String, done: Bool)] {
        [
            ("write the README", true),
            ("record the hero screencast", true),
            ("tag v1.0 and open the gates", false),
            ("feed the monster something nice", false)
        ]
    }

    private var upNext: [(title: String, done: Bool)] {
        [
            ("sand down the rough edges", false),
            ("teach the monster new tricks", false),
            ("write the release notes", false),
            ("swap in fresh screenshots", false),
            ("re-record the hero screencast", false),
            ("bump the version and tag it", false),
            ("notarize the dmg", false),
            ("tell the group chat", false),
            ("order launch-day pizza", false),
            ("take a well-earned nap", false),
            ("dream up the next feature", false)
        ]
    }
}

extension ScreencastRunner {
    /// Scroll panes over the demo window: the sidebar and content pane grow
    /// outlines with letter badges — drawn by the real overlay view — and
    /// typing the content pane's letter starts scrolling it. A few j presses
    /// glide the checklist up past the fold while the active pane keeps its
    /// outline, just like the live mode.
    static func scrollScene(recorder: Recorder, window: NSWindow) {
        let demo = DemoWindowModel()
        let overlay = HintOverlayModel()
        let state = CastState(caption: "⌃⇧S — pick a pane; J and K become the scroll wheel")
        show(CastCanvas(state: state, panelSize: DemoWindowLayout.overlaySize,
                        content: DemoOverlayScene(model: demo,
                                                  overlay: HintOverlayHost(model: overlay))),
             in: window)
        SnapshotRunner.settle(0.4)

        recorder.begin("scroll")
        recorder.fade(state, to: 1, over: 0.3)
        recorder.hold(0.6)

        // Both panes badge up, sidebar first — the same AX-walk order the live
        // scanner reports, so the content pane gets the last label.
        let margin = DemoWindowLayout.overlayMargin
        let panes = [DemoWindowLayout.sidebarPane, DemoWindowLayout.contentPane]
            .map { $0.offsetBy(dx: margin, dy: margin) }
        let labels = HintLabels.labels(count: panes.count)
        overlay.panes = zip(panes, labels).map { HintOverlayView.Pane(rect: $0, label: $1) }
        recorder.hold(1.4)

        // Type the content pane's letter: its single-letter label commits, the
        // wash drops away, and only the active outline and key legend remain.
        guard let picked = panes.last, let label = labels.last else {
            SnapshotRunner.fail("no scroll panes to pick in the demo window")
        }
        overlay.typed = label
        recorder.hold(0.15)
        overlay.typed = ""
        overlay.panes = [HintOverlayView.Pane(rect: picked, label: nil)]
        overlay.bannerEdge = .bottom
        overlay.banner = "J/K to scroll · Esc to stop"
        recorder.hold(0.6)

        // Three j presses, each a short glide — wheel pulses, not a free scroll.
        for _ in 0..<3 {
            let start = demo.contentScroll
            recorder.animate(over: 0.35) { progress in
                demo.contentScroll = start + 70 * progress
            }
            recorder.hold(0.3)
        }
        recorder.hold(0.9)

        recorder.end(fading: state)
    }
}
#endif
