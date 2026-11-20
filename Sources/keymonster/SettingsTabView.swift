import SwiftUI

/// How tall a settings tab may get. The window sizes itself to the tab's
/// content, so without a cap a long list (say, many always-scroll sites) would
/// push the bottom of the window off the screen; past the cap the tab scrolls.
enum SettingsTabHeight {
    /// Room the window needs besides the tab's content: title bar, tab strip,
    /// and a margin so the window never touches the dock or menu bar.
    static let chrome: CGFloat = 160

    static func clamped(content: CGFloat, screenHeight: CGFloat) -> CGFloat {
        min(content, max(screenHeight - chrome, 300))
    }
}

/// One Settings tab: a description of the feature up top, then its sections.
/// Hand-rolled cards in a plain stack (no Form) make the tab's ideal height its
/// content height so the window can size to it; a ScrollView takes over only
/// when the content outgrows `SettingsTabHeight`.
struct SettingsTabView<Content: View>: View {
    let description: String
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat?

    var body: some View {
        // The ScrollView is pinned to the content's measured height (up to the
        // cap) so the window still reports each tab's natural size.
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(description)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                content
            }
            .padding(20)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { contentHeight = $0 })
        }
        .frame(height: contentHeight.map {
            SettingsTabHeight.clamped(
                content: $0, screenHeight: NSScreen.main?.visibleFrame.height ?? 800
            )
        })
    }
}
