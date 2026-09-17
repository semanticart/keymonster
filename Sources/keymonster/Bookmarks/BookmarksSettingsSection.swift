import SwiftUI
import AppKit

/// The Bookmarks tab's content: the shortcut, the bookmarks file's path and
/// count, buttons to edit or reveal it, and the latest failure when there is
/// one. There is no in-app add/edit/delete list — bookmarks are maintained by
/// hand in the CSV file, opened through "Edit Bookmarks…".
struct BookmarksSettingsSection: View {
    @ObservedObject var settings: AppSettings
    let isConflicting: Bool
    @ObservedObject private var scriptLog = ScriptLog.shared
    @State private var bookmarkCount = BookmarksStore.load().count

    private var lastFailure: ScriptLog.Failure? {
        guard let failure = scriptLog.lastFailure,
              failure.script == BookmarksEditorController.logName else { return nil }
        return failure
    }

    var body: some View {
        SettingsSection(
            header: "Bookmarks",
            footer: "One title,url per line in the file below — quote a title that contains a "
                + "comma. An optional title,url header line is skipped automatically. The second "
                + "column can also be a local path (/… or ~/…), opened and iconed as a file or "
                + "folder instead of a website. Fuzzy-find favors the title but also matches the "
                + "url; Return opens the highlighted bookmark."
        ) {
            ShortcutSettingRow(
                title: "Search Bookmarks",
                shortcut: $settings.bookmarksShortcut,
                isConflicting: isConflicting
            )

            HStack {
                Text(BookmarksStore.defaultURL().path)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(bookmarkCount) bookmark\(bookmarkCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Edit Bookmarks…") {
                    BookmarksEditorController.shared.trigger()
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([BookmarksStore.defaultURL()])
                }
                Spacer()
            }

            if let lastFailure {
                ScriptFailureNotice(failure: lastFailure)
            }
        }
        .onAppear {
            refreshCount()
            BookmarksEditorController.shared.onFinish = refreshCount
        }
    }

    private func refreshCount() {
        bookmarkCount = BookmarksStore.load().count
    }
}
