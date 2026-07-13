import SwiftUI
import AppKit

// MARK: - Detail Scroll Host (right panel)

/// The right panel: the full content of the selected item, top-anchored and
/// scrollable. This is a plain SwiftUI `ScrollView` because it top-anchors and
/// sizes content reliably regardless of height — the hand-rolled NSScrollView it
/// replaced left short content sitting too low and tall content clipped above the
/// fold. `ScrollViewProbe` hands the backing NSScrollView to the view model so
/// Ctrl-J/K can still drive it programmatically.
struct DetailScrollHost: View {
    let item: ClipItem
    let viewModel: HistoryViewModel

    var body: some View {
        ScrollView {
            DetailContent(item: item)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(ScrollViewProbe(viewModel: viewModel))
        }
        // A new item resets to the top; SwiftUI otherwise keeps the prior offset.
        .onChange(of: item.id) { viewModel.scrollDetailToTop() }
    }
}

/// A zero-size NSView whose only job is to surface the NSScrollView that SwiftUI's
/// `ScrollView` is built on, so Ctrl-J/K can scroll it. `enclosingScrollView` is
/// nil until the view is in the hierarchy, so we capture it asynchronously.
private struct ScrollViewProbe: NSViewRepresentable {
    let viewModel: HistoryViewModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        capture(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        capture(from: nsView)
    }

    private func capture(from view: NSView) {
        DispatchQueue.main.async {
            if let scrollView = view.enclosingScrollView {
                viewModel.detailScrollView = scrollView
            }
        }
    }
}

// MARK: - Detail Content

private struct DetailContent: View {
    let item: ClipItem

    var body: some View {
        Group {
            switch item.content {
            case .text(let text):
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 13 * uiScale, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .image(let img):
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .fileURLs(let urls):
                VStack(alignment: .leading, spacing: 4 * uiScale) {
                    ForEach(urls, id: \.self) { url in
                        Text(url.path)
                            .font(.system(size: 12 * uiScale, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Top-align so short content hugs the top instead of centering.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14 * uiScale)
    }
}
