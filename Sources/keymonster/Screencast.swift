import SwiftUI
import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "screencast")

/// Scripted, headless screencast of the real panels for the website hero.
///
/// `keymonster screencast [--out DIR] [--fps N]` drives the real panels and
/// overlays through a choreographed demo — click hints, the grid loupe, text
/// jump, menu search, then the clipboard history — against the same seeded
/// demo content as `snapshot --demo`, capturing one PNG per frame plus a
/// `poster.png`. Nothing on screen is real user data, so the result is safe
/// to publish. `make site-cast` records the frames and encodes the video.
///
/// The scenes render on a shared fixed-size canvas that paints the site's
/// hero background behind the panel, so the encoded video (which has no alpha)
/// sits seamlessly on the page and the cut between scenes doesn't reframe.
@MainActor
enum ScreencastRunner {
    private static let canvasSize = NSSize(width: 760 * uiScale, height: 600 * uiScale)
    private static let historyPanelSize = CGSize(width: 620 * uiScale, height: 500 * uiScale)
    private static let menuPanelSize = CGSize(width: 540 * uiScale, height: 460 * uiScale)

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let outDir = SnapshotRunner.option("--out")
            ?? (NSTemporaryDirectory() + "keymonster-screencast")
        let fps = SnapshotRunner.option("--fps").flatMap(Double.init) ?? 30
        let outURL = URL(fileURLWithPath: outDir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
        } catch {
            SnapshotRunner.fail("could not create output dir \(outDir): \(error)")
        }

        let window = SnapshotRunner.makeWindow(size: canvasSize)
        window.orderFront(nil)
        let recorder = Recorder(window: window, outURL: outURL, fps: fps)

        hintScene(recorder: recorder, window: window)
        gridScene(recorder: recorder, window: window)
        textJumpScene(recorder: recorder, window: window)
        menuScene(recorder: recorder, window: window)
        historyScene(recorder: recorder, window: window)

        print(outDir)
        log.info("wrote \(recorder.frames) frame(s) to \(outDir)")
        exit(recorder.frames == 0 ? 1 : 0)
    }

    // MARK: - Scenes

    /// Open on the full history, type "monster" to filter, walk the matches,
    /// then clear and land on the image entry's full preview.
    private static func historyScene(recorder: Recorder, window: NSWindow) {
        let history = ClipboardHistory()
        do {
            history.configure(store: try SQLiteClipStore.inMemory())
        } catch {
            SnapshotRunner.fail("could not open in-memory store: \(error)")
        }
        SnapshotRunner.seedDemoHistory(into: history)

        let model = HistoryViewModel(history: history)
        model.prepareForPresentation()

        let state = CastState(caption: "⌃⇧V — everything you've copied, searchable")
        show(CastCanvas(state: state, panelSize: historyPanelSize,
                        content: MenuContent(history: history, model: model)),
             in: window)
        // Let the first render finish before scripting: the search field's
        // initial focus writes the binding back and re-selects the first item.
        SnapshotRunner.settle(0.5)

        recorder.fade(state, to: 1, over: 0.3)
        recorder.hold(0.8)

        for (index, char) in "monster".enumerated() {
            model.searchText.append(char)
            // Slightly uneven cadence so the typing reads as human.
            recorder.hold(index.isMultiple(of: 2) ? 0.16 : 0.11)
        }
        recorder.hold(0.8)

        model.moveSelection(by: 1)
        recorder.hold(0.5)
        model.moveSelection(by: 1)
        recorder.hold(1.0)

        while !model.searchText.isEmpty {
            model.searchText.removeLast()
            recorder.hold(0.06)
        }
        model.selectedID = history.items.first {
            if case .image = $0.content { return true } else { return false }
        }?.id
        recorder.hold(1.5)

        recorder.fade(state, to: 0, over: 0.3)
    }

    /// Menu search over Safari: type "re", walk the ranked matches.
    private static func menuScene(recorder: Recorder, window: NSWindow) {
        let model = MenuFinderViewModel()
        model.present(items: SnapshotRunner.demoMenuItems(), appName: "Safari")

        let state = CastState(caption: "⌃⇧M — run any menu item by name")
        show(CastCanvas(state: state, panelSize: menuPanelSize,
                        content: MenuFinderContent(model: model)),
             in: window)
        SnapshotRunner.settle(0.4)

        recorder.fade(state, to: 1, over: 0.3)
        recorder.hold(0.7)

        model.searchText = "r"
        recorder.hold(0.18)
        model.searchText = "re"
        recorder.hold(0.9)

        model.moveSelection(by: 1)
        recorder.hold(0.5)
        model.moveSelection(by: 1)
        recorder.hold(0.9)

        recorder.fade(state, to: 0, over: 0.3)
    }

    static func show(_ canvas: some View, in window: NSWindow) {
        let hosting = NSHostingView(rootView: canvas)
        hosting.frame = NSRect(origin: .zero, size: window.frame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
    }

    // MARK: - Frame recording

    /// Captures one PNG per frame while pumping the run loop, so SwiftUI's own
    /// animations (list scrolling, selection moves) land on film in between the
    /// scripted state changes.
    @MainActor
    final class Recorder {
        private let window: NSWindow
        private let outURL: URL
        private let fps: Double
        private(set) var frames = 0

        init(window: NSWindow, outURL: URL, fps: Double) {
            self.window = window
            self.outURL = outURL
            self.fps = fps
        }

        /// Let `seconds` of scene time elapse, capturing every frame.
        func hold(_ seconds: TimeInterval) {
            let count = max(1, Int((seconds * fps).rounded()))
            for _ in 0..<count {
                SnapshotRunner.settle(1 / fps)
                snap()
            }
        }

        /// Linearly ramp the scene's foreground opacity while capturing, for
        /// scene cuts and a seamless loop point.
        func fade(_ state: CastState, to target: Double, over seconds: TimeInterval) {
            let count = max(1, Int((seconds * fps).rounded()))
            let start = state.opacity
            for step in 1...count {
                state.opacity = start + (target - start) * Double(step) / Double(count)
                SnapshotRunner.settle(1 / fps)
                snap()
            }
        }

        /// Step a hand-driven animation: calls `update` with progress 0→1 once
        /// per frame, capturing each one.
        func animate(over seconds: TimeInterval, _ update: (Double) -> Void) {
            let count = max(1, Int((seconds * fps).rounded()))
            for step in 1...count {
                update(Double(step) / Double(count))
                SnapshotRunner.settle(1 / fps)
                snap()
            }
        }

        /// Save the current frame again as the video's poster image.
        func poster() {
            _ = SnapshotRunner.capture(window, to: outURL.appendingPathComponent("poster.png"))
        }

        private func snap() {
            let url = outURL.appendingPathComponent(String(format: "frame-%05d.png", frames))
            if SnapshotRunner.capture(window, to: url) { frames += 1 }
        }
    }

    // MARK: - Canvas

    /// Foreground opacity and caption for one scene. The recorder animates the
    /// opacity; the backdrop stays at full strength so fades never flash.
    final class CastState: ObservableObject {
        @Published var opacity: Double = 0
        let caption: String

        init(caption: String) {
            self.caption = caption
        }
    }

    /// The panel centered on the site's hero backdrop, with a one-line caption
    /// naming the chord and the feature underneath.
    struct CastCanvas<Content: View>: View {
        @ObservedObject var state: CastState
        let panelSize: CGSize
        let content: Content

        var body: some View {
            ZStack {
                backdrop
                VStack(spacing: 16 * uiScale) {
                    content.frame(width: panelSize.width, height: panelSize.height)
                    Text(state.caption)
                        .font(.system(size: 12 * uiScale, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .opacity(state.opacity)
            }
            .ignoresSafeArea()
        }

        /// The website hero's background: its page color with the same two
        /// soft radial glows, so the video blends into the page around it.
        private var backdrop: some View {
            let fur = Color(red: 69 / 255, green: 179 / 255, blue: 240 / 255)
            let furDeep = Color(red: 24 / 255, green: 104 / 255, blue: 182 / 255)
            return ZStack {
                Color(red: 10 / 255, green: 17 / 255, blue: 24 / 255)
                RadialGradient(
                    colors: [fur.opacity(0.14), .clear],
                    center: UnitPoint(x: 0.78, y: 0.12),
                    startRadius: 0, endRadius: 430 * uiScale
                )
                RadialGradient(
                    colors: [furDeep.opacity(0.18), .clear],
                    center: UnitPoint(x: 0.12, y: 0.85),
                    startRadius: 0, endRadius: 380 * uiScale
                )
            }
        }
    }
}
