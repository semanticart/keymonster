import SwiftUI
import AppKit

/// The fabricated "app you'd normally mouse around" that the screencast's click
/// scenes overlay: a plausible dark-mode window with a sidebar, toolbar buttons,
/// a checklist, a link, and a Publish button. Its geometry lives in
/// `DemoWindowLayout` so the hint badges and grid cells the scenes draw with the
/// real overlay views line up with what the window shows.
enum DemoWindowLayout {
    static let size = CGSize(width: 920, height: 640)
    /// Overlay views extend this far past every window edge, because real hint
    /// badges hang just outside the window they label.
    static let overlayMargin: CGFloat = 40

    static let titleBarHeight: CGFloat = 40
    static let shareButton = CGRect(x: 736, y: 7, width: 76, height: 26)
    static let newButton = CGRect(x: 824, y: 7, width: 72, height: 26)
    static let sidebarWidth: CGFloat = 200
    static let sidebarRows = [
        CGRect(x: 12, y: 56, width: 176, height: 40),
        CGRect(x: 12, y: 100, width: 176, height: 40),
        CGRect(x: 12, y: 144, width: 176, height: 40)
    ]
    static let link = CGRect(x: 232, y: 300, width: 320, height: 20)
    static let publishButton = CGRect(x: 796, y: 582, width: 100, height: 34)

    static var publishCenter: CGPoint { CGPoint(x: publishButton.midX, y: publishButton.midY) }

    /// The window's rect in overlay-view coordinates (shifted by the margin).
    static var windowRect: CGRect {
        CGRect(origin: CGPoint(x: overlayMargin, y: overlayMargin), size: size)
    }

    static var overlaySize: CGSize {
        CGSize(width: size.width + overlayMargin * 2, height: size.height + overlayMargin * 2)
    }
}

/// Click feedback the scenes trigger on the demo window: a ripple ring the
/// recorder steps through frame by frame, plus a pressed look on the button.
@MainActor
final class DemoWindowModel: ObservableObject {
    /// 0...1 ripple progress at `rippleCenter`, or nil for no ripple.
    @Published var ripple: Double?
    @Published var rippleCenter: CGPoint = .zero
    @Published var publishPressed = false
    /// Swaps the checklist pane for the markdown editor (the text-jump scene).
    @Published var editorMode = false
    /// The editor's caret as (line, column) into `DemoEditorLayout.lines`.
    @Published var caret: (line: Int, column: Int)?
}

struct DemoWindow: View {
    @ObservedObject var model: DemoWindowModel

    private let background = Color(red: 0.094, green: 0.106, blue: 0.129)
    private let chrome = Color.white.opacity(0.055)
    private let border = Color.white.opacity(0.12)
    private let text = Color.white.opacity(0.86)
    private let faint = Color.white.opacity(0.42)
    private let accent = Color(red: 0.12, green: 0.49, blue: 0.80)
    private let linkBlue = Color(red: 0.35, green: 0.66, blue: 0.95)

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(background)
            titleBar
            sidebar
            if model.editorMode { editorPane } else { content }
            if let progress = model.ripple {
                Circle()
                    .stroke(linkBlue, lineWidth: 3)
                    .frame(width: 30, height: 30)
                    .scaleEffect(0.5 + progress * 1.8)
                    .opacity(1 - progress)
                    .position(model.rippleCenter)
            }
        }
        .frame(width: DemoWindowLayout.size.width, height: DemoWindowLayout.size.height)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 1))
        .compositingGroup()
        .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
    }

    private var titleBar: some View {
        ZStack(alignment: .topLeading) {
            UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
                .fill(chrome)
                .frame(height: DemoWindowLayout.titleBarHeight)
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                Circle().fill(Color(red: 0.16, green: 0.78, blue: 0.25)).frame(width: 12, height: 12)
            }
            .padding(.leading, 16)
            .frame(height: DemoWindowLayout.titleBarHeight)
            Text("Field Notes")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(faint)
                .frame(width: DemoWindowLayout.size.width, height: DemoWindowLayout.titleBarHeight)
            chromeButton("Share", in: DemoWindowLayout.shareButton)
            chromeButton("+ New", in: DemoWindowLayout.newButton)
        }
    }

    private func chromeButton(_ title: String, in rect: CGRect) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium)).foregroundStyle(text)
            .frame(width: rect.width, height: rect.height)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.09)))
            .position(x: rect.midX, y: rect.midY)
    }

    private var sidebar: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(chrome)
                .frame(width: DemoWindowLayout.sidebarWidth)
                .padding(.top, DemoWindowLayout.titleBarHeight)
            let titles = [("Inbox", "12"), ("Drafts", "3"), ("Archive", "")]
            ForEach(Array(zip(DemoWindowLayout.sidebarRows, titles).enumerated()),
                    id: \.offset) { index, pair in
                let (rect, title) = pair
                HStack {
                    Text(title.0).font(.system(size: 13)).foregroundStyle(text)
                    Spacer()
                    Text(title.1).font(.system(size: 11)).foregroundStyle(faint)
                }
                .padding(.horizontal, 12)
                .frame(width: rect.width, height: rect.height)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(index == 1 ? Color.white.opacity(0.08) : .clear)
                )
                .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private var content: some View {
        ZStack(alignment: .topLeading) {
            Text("Launch checklist")
                .font(.system(size: 20, weight: .bold)).foregroundStyle(text)
                .position(x: 232 + 82, y: 84)
            ForEach(Array(checklist.enumerated()), id: \.offset) { index, line in
                HStack(spacing: 10) {
                    Text(line.done ? "✓" : "▢")
                        .font(.system(size: 13)).foregroundStyle(line.done ? accent : faint)
                    Text(line.title).font(.system(size: 13)).foregroundStyle(text)
                        .strikethrough(line.done, color: faint)
                }
                .frame(width: 400, height: 24, alignment: .leading)
                .position(x: 232 + 200, y: 132 + CGFloat(index) * 34)
            }
            Text("github.com/semanticart/keymonster")
                .font(.system(size: 13)).underline().foregroundStyle(linkBlue)
                .frame(width: DemoWindowLayout.link.width,
                       height: DemoWindowLayout.link.height, alignment: .leading)
                .position(x: DemoWindowLayout.link.midX, y: DemoWindowLayout.link.midY)
            Text("Publish")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: DemoWindowLayout.publishButton.width,
                       height: DemoWindowLayout.publishButton.height)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(accent.opacity(model.publishPressed ? 0.7 : 1)))
                .position(x: DemoWindowLayout.publishButton.midX,
                          y: DemoWindowLayout.publishButton.midY)
        }
    }

    private var checklist: [(title: String, done: Bool)] {
        [
            ("write the README", true),
            ("record the hero screencast", true),
            ("tag v1.0 and open the gates", false),
            ("feed the monster something nice", false)
        ]
    }
}

// MARK: - Overlay hosting

/// Hosts the real `HintOverlayView` over the demo window so the screencast's
/// hint badges are drawn by the same code the live overlay uses.
@MainActor
final class HintOverlayModel: ObservableObject {
    @Published var badges: [HintOverlayView.Badge] = []
    @Published var typed = ""
    @Published var banner: String?
}

struct HintOverlayHost: NSViewRepresentable {
    @ObservedObject var model: HintOverlayModel

    func makeNSView(context: Context) -> HintOverlayView {
        let view = HintOverlayView(frame: CGRect(origin: .zero, size: DemoWindowLayout.overlaySize))
        view.windowRegion = DemoWindowLayout.windowRect
        return view
    }

    func updateNSView(_ view: HintOverlayView, context: Context) {
        view.badges = model.badges
        view.typed = model.typed
        view.banner = model.banner
    }
}

/// Hosts the real `GridOverlayView` likewise, fed the same content the live
/// `GridOverlay` would compute.
@MainActor
final class GridOverlayModel: ObservableObject {
    enum Content {
        case none
        case hints(cells: [GridOverlayView.HintCell], typed: String)
        case grid(region: CGRect, panel: CGRect, image: CGImage?)
    }

    @Published var content: Content = .none
}

struct GridOverlayHost: NSViewRepresentable {
    @ObservedObject var model: GridOverlayModel

    func makeNSView(context: Context) -> GridOverlayView {
        GridOverlayView(frame: CGRect(origin: .zero, size: DemoWindowLayout.overlaySize))
    }

    func updateNSView(_ view: GridOverlayView, context: Context) {
        switch model.content {
        case .none:
            view.showHints(cells: [], typed: "")
        case let .hints(cells, typed):
            view.showHints(cells: cells, typed: typed)
        case let .grid(region, panel, image):
            view.showGrid(region: region, panel: panel, image: image)
        }
    }
}

/// The demo window with an overlay floated on top, both sized so overlay-view
/// coordinates equal window coordinates plus the margin.
struct DemoOverlayScene<Overlay: View>: View {
    @ObservedObject var model: DemoWindowModel
    let overlay: Overlay

    var body: some View {
        ZStack {
            DemoWindow(model: model)
            overlay
        }
        .frame(width: DemoWindowLayout.overlaySize.width,
               height: DemoWindowLayout.overlaySize.height)
    }
}

// MARK: - The click scenes

extension ScreencastRunner {
    /// Click hints over the demo window: badges pop onto every clickable
    /// element (the crowded sidebar shares one green area label), then typing a
    /// label clicks its element.
    static func hintScene(recorder: Recorder, window: NSWindow) {
        let demo = DemoWindowModel()
        let overlay = HintOverlayModel()
        let state = CastState(caption: "⌃⇧F — every clickable thing grows a key; type it to click")
        show(CastCanvas(state: state, panelSize: DemoWindowLayout.overlaySize,
                        content: DemoOverlayScene(model: demo,
                                                  overlay: HintOverlayHost(model: overlay))),
             in: window)
        SnapshotRunner.settle(0.4)

        recorder.begin("hints")
        recorder.fade(state, to: 1, over: 0.3)
        recorder.hold(0.7)

        overlay.badges = hintBadges()
        recorder.hold(1.2)
        recorder.poster()
        recorder.hold(0.3)

        // Typing the Publish button's single-letter label commits immediately.
        overlay.typed = overlay.badges.last?.label ?? ""
        recorder.hold(0.15)
        overlay.badges = []
        overlay.typed = ""
        click(demo, at: DemoWindowLayout.publishCenter, recorder: recorder, pressing: true)
        recorder.hold(0.7)

        recorder.end(fading: state)
    }

    /// Grid click over the demo window: the initial labelled grid, a two-letter
    /// pick, the loupe magnifying the picked cell with the keyboard grid and
    /// Return target on top, then the click.
    static func gridScene(recorder: Recorder, window: NSWindow) {
        let demo = DemoWindowModel()
        let overlay = GridOverlayModel()
        let state = CastState(caption: "⌃⇧G — no element? A keyboard-shaped grid zooms you in")
        show(CastCanvas(state: state, panelSize: DemoWindowLayout.overlaySize,
                        content: DemoOverlayScene(model: demo,
                                                  overlay: GridOverlayHost(model: overlay))),
             in: window)
        SnapshotRunner.settle(0.4)

        // Screenshot the pristine window once — crops of it feed the loupe the
        // way WindowCapture screenshots the real screen in the live app.
        let renderer = ImageRenderer(content: DemoWindow(model: DemoWindowModel()))
        renderer.scale = 2
        guard let base = renderer.nsImage?.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ) else {
            SnapshotRunner.fail("could not render the demo window for the loupe")
        }

        let margin = DemoWindowLayout.overlayMargin
        let target = CGPoint(x: DemoWindowLayout.publishCenter.x + margin,
                             y: DemoWindowLayout.publishCenter.y + margin)

        recorder.begin("grid")
        recorder.fade(state, to: 1, over: 0.3)
        recorder.hold(0.5)

        let cells = GridHints.cells(of: DemoWindowLayout.windowRect)
        guard let picked = cells.first(where: { $0.rect.contains(target) }) else {
            SnapshotRunner.fail("no initial grid cell over the demo target")
        }
        let hintCells = cells.map { GridOverlayView.HintCell(label: $0.label, rect: $0.rect) }
        overlay.content = .hints(cells: hintCells, typed: "")
        recorder.hold(1.4)
        overlay.content = .hints(cells: hintCells, typed: String(picked.label.prefix(1)))
        recorder.hold(0.5)

        overlay.content = loupe(magnifying: picked.rect, from: base)
        recorder.hold(1.6)

        overlay.content = .none
        click(demo, at: DemoWindowLayout.publishCenter, recorder: recorder, pressing: false)
        recorder.hold(0.6)

        recorder.end(fading: state)
    }

    /// One badge per demo target, laid just leading of what it labels — the
    /// crowded sidebar rows merge into a single green area badge, like
    /// `HintGrouping` does live. Labels come from the real generator.
    private static func hintBadges() -> [HintOverlayView.Badge] {
        let margin = DemoWindowLayout.overlayMargin
        let size = BadgeMetrics.size(forLabelLength: 1)
        let sidebar = DemoWindowLayout.sidebarRows.reduce(CGRect.null) { $0.union($1) }
        // (target, is the sidebar cluster) in AX-walk order: chrome, sidebar,
        // then content — so the Publish button gets the last label.
        let targets: [(rect: CGRect, cluster: Bool)] = [
            (DemoWindowLayout.shareButton, false),
            (DemoWindowLayout.newButton, false),
            (sidebar, true),
            (DemoWindowLayout.link, false),
            (DemoWindowLayout.publishButton, false)
        ]
        let labels = HintLabels.labels(count: targets.count)
        return zip(targets, labels).map { target, label in
            let shifted = target.rect.offsetBy(dx: margin, dy: margin)
            let badge = CGRect(
                x: shifted.minX - size.width - 6,
                y: shifted.midY - size.height / 2,
                width: size.width, height: size.height
            )
            return HintOverlayView.Badge(
                rect: badge, label: label,
                area: target.cluster ? shifted : nil,
                caret: HintOverlayView.caretDirection(from: badge, toward: shifted)
            )
        }
    }

    /// The loupe for `region`: panel geometry from the real `GridZoom`, pixels
    /// cropped out of the pre-rendered 2x window screenshot.
    private static func loupe(
        magnifying region: CGRect, from base: CGImage
    ) -> GridOverlayModel.Content {
        let margin = DemoWindowLayout.overlayMargin
        let panel = GridZoom.panel(magnifying: region, into: DemoWindowLayout.windowRect)
        let pixels = region.offsetBy(dx: -margin, dy: -margin)
            .applying(CGAffineTransform(scaleX: 2, y: 2))
        return .grid(region: region, panel: panel, image: base.cropping(to: pixels))
    }

    /// A click landing on the demo window: a ripple ring stepped frame by frame
    /// (and, for a button, a brief pressed look).
    private static func click(
        _ demo: DemoWindowModel, at point: CGPoint, recorder: Recorder, pressing: Bool
    ) {
        demo.rippleCenter = point
        demo.publishPressed = pressing
        recorder.animate(over: 0.45) { progress in
            demo.ripple = progress
            if progress > 0.4 { demo.publishPressed = false }
        }
        demo.ripple = nil
    }
}
