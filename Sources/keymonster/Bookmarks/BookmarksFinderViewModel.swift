import Foundation

/// Drives the bookmarks-finder panel's search-first interaction: it holds the
/// loaded bookmarks and the query, derives the fuzzy-ranked list, and tracks
/// the keyboard selection so the panel can move it (Ctrl-N/Ctrl-P, arrows) and
/// run it (Return). Kept AppKit-free, mirroring `MenuFinderViewModel` — the
/// controller owns opening the resulting URL.
@MainActor
final class BookmarksFinderViewModel: ObservableObject {
    /// The current query. Editing it re-selects the best match.
    @Published var searchText: String = "" {
        didSet {
            refresh()
            selectFirst()
        }
    }

    /// The id of the keyboard-highlighted row, if any.
    @Published var selectedID: Int?

    /// Every bookmark loaded from the CSV file, in file order.
    @Published private(set) var bookmarks: [Bookmark] = []

    /// Bumped each time the panel is presented so the view can refocus the field.
    @Published private(set) var focusBump = 0

    /// The rows for the current query: provider suggestions first (a script
    /// that recognises the query outranks fuzzy matching), then the bookmarks
    /// matching it, best title match first (or all, in file order). Cached
    /// because running scripts on every read would be wasteful.
    @Published private(set) var filteredBookmarks: [Bookmark] = []

    private var providers: [SuggestionProvider] = []

    var selectedBookmark: Bookmark? {
        guard let selectedID else { return nil }
        return filteredBookmarks.first { $0.id == selectedID }
    }

    /// Load a fresh read of the bookmarks file and reset to a blank query with
    /// the first bookmark selected. Call each time the panel is shown.
    func present(bookmarks: [Bookmark], providers: [SuggestionProvider] = []) {
        self.bookmarks = bookmarks
        self.providers = providers
        searchText = ""
        refresh()
        selectFirst()
        focusBump &+= 1
    }

    /// Move the highlight by `delta` rows through the filtered list, clamped to
    /// the ends (positive = down).
    func moveSelection(by delta: Int) {
        let bookmarks = filteredBookmarks
        guard !bookmarks.isEmpty else { selectedID = nil; return }
        if let id = selectedID, let index = bookmarks.firstIndex(where: { $0.id == id }) {
            let next = min(max(index + delta, 0), bookmarks.count - 1)
            selectedID = bookmarks[next].id
        } else {
            selectedID = delta >= 0 ? bookmarks.first?.id : bookmarks.last?.id
        }
    }

    /// The highlighted bookmark to open, or nil if nothing is selected.
    func activateSelection() -> Bookmark? {
        selectedBookmark
    }

    /// Provider rows get negative ids so they can't collide with the
    /// non-negative file-order ids of bookmarks.
    private func refresh() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var suggested: [Bookmark] = []
        if !query.isEmpty {
            for provider in providers {
                for item in provider.suggestions(for: query) {
                    suggested.append(Bookmark(id: -(suggested.count + 1), title: item.title, url: item.url))
                }
            }
        }
        filteredBookmarks = suggested + BookmarkFilter.filter(bookmarks, query: searchText)
    }

    private func selectFirst() {
        selectedID = filteredBookmarks.first?.id
    }
}
