import Foundation

/// Where the user's bookmarks live: a plain `title,url` CSV file they edit by
/// hand (or through "Edit Bookmarks…" in Settings, see `BookmarksEditorController`)
/// instead of an in-app add/edit/delete list. Loaded fresh every time the
/// finder panel opens — see `BookmarksFinderController.show()` — so there's no
/// need to watch the file for changes.
enum BookmarksStore {
    static let fileName = "bookmarks.csv"
    private static let header = "title,url\n"

    /// The on-disk location of the bookmarks file, alongside the clip history
    /// database (`ClipStore.defaultURL()`). Does not create anything.
    static func defaultURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("keymonster")
            .appendingPathComponent(fileName)
    }

    /// Creates the containing directory and a header-only file at `url` if
    /// nothing is there yet. Never touches an existing file.
    static func ensureExists(at url: URL = defaultURL()) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try header.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Reads and parses the bookmarks file. A missing file or one that can't be
    /// read as UTF-8 text yields an empty list, with no side effect — this
    /// never creates the file.
    static func load(from url: URL = defaultURL()) -> [Bookmark] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return BookmarkCSV.parse(text)
    }
}
