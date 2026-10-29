import SwiftUI
import AppKit

/// The Palette tab's content, in three sections: the shortcut; the bookmarks
/// file's path and count, buttons to edit or reveal it, and the latest failure
/// when there is one; and the providers folder with a button that copies
/// LLM-ready instructions for writing a provider. There is no in-app add/edit/delete list — bookmarks are maintained by
/// hand in the CSV file, opened through "Edit Bookmarks…".
struct BookmarksSettingsSection: View {
    @ObservedObject var settings: AppSettings
    let isConflicting: Bool
    @ObservedObject private var scriptLog = ScriptLog.shared
    @State private var bookmarkCount = BookmarksStore.load().count
    @State private var copiedInstructions = false

    private var lastFailure: ScriptLog.Failure? {
        guard let failure = scriptLog.lastFailure,
              failure.script == BookmarksEditorController.logName else { return nil }
        return failure
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            shortcutSection
            bookmarksSection
            providersSection
        }
        .onAppear {
            refreshCount()
            BookmarksEditorController.shared.onFinish = refreshCount
        }
    }

    private var shortcutSection: some View {
        SettingsSection(header: "Palette") {
            ShortcutSettingRow(
                title: "Open Palette",
                shortcut: $settings.bookmarksShortcut,
                isConflicting: isConflicting
            )
        }
    }

    private var bookmarksSection: some View {
        SettingsSection(
            header: "Bookmarks",
            footer: "One title,url per line in the file below — quote a title that contains a "
                + "comma. An optional title,url header line is skipped automatically. The second "
                + "column can also be a local path (/… or ~/…), opened and iconed as a file or "
                + "folder instead of a website. Fuzzy-find favors the title but also matches the "
                + "url; Return opens the highlighted row."
        ) {
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
    }

    private var providersSection: some View {
        SettingsSection(
            header: "Providers",
            footer: "A provider is a JavaScript file whose suggest(query) returns [{title, url}] "
                + "rows shown above your bookmarks — for example, turning a pasted UUID into links. "
                + "Copy the instructions and paste them into an LLM agent to have it write one."
        ) {
            Text(ProviderStore.defaultDirectory().path)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)

            HStack {
                Button("Open Providers Folder") {
                    openProvidersFolder()
                }
                Button(copiedInstructions ? "Copied" : "Copy Instructions for an LLM") {
                    copyInstructions()
                }
                Spacer()
            }
        }
    }

    /// Creates the folder first if need be, so the button always lands somewhere.
    private func openProvidersFolder() {
        let directory = ProviderStore.defaultDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private func copyInstructions() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ProviderInstructions.text(), forType: .string)
        copiedInstructions = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedInstructions = false
        }
    }

    private func refreshCount() {
        bookmarkCount = BookmarksStore.load().count
    }
}
