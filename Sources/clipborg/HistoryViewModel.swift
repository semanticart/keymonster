import Foundation
import Combine

/// Drives the history panel's search-first interaction: it owns the search query
/// and the keyboard selection, derives the filtered list, and lets the panel
/// move the selection (Ctrl-N / Ctrl-P, arrows) and activate it (Return).
@MainActor
final class HistoryViewModel: ObservableObject {
    /// The current search query. Editing it re-selects the first match.
    @Published var searchText: String = "" {
        didSet { selectFirst() }
    }

    /// The id of the keyboard-highlighted row, if any.
    @Published var selectedID: UUID?

    /// Bumped each time the panel is presented so the view can refocus the field.
    @Published private(set) var focusBump = 0

    let history: ClipboardHistory
    private var cancellable: AnyCancellable?

    init(history: ClipboardHistory) {
        self.history = history
        // Keep the selection valid as items are added, removed, or cleared.
        cancellable = history.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.revalidateSelection() }
        }
    }

    /// The history filtered by the current query, newest first.
    var filteredItems: [ClipItem] {
        Self.filter(history.items, query: searchText)
    }

    /// Pure filter used by the view model and exercised directly in tests.
    static func filter(_ items: [ClipItem], query: String) -> [ClipItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.matches(lowercasedQuery: trimmed) }
    }

    /// Reset to search mode with the first item highlighted, and ask the view to
    /// focus the search field. Call this whenever the panel is shown.
    func prepareForPresentation() {
        searchText = ""
        selectFirst()
        focusBump &+= 1
    }

    /// Move the highlight by `delta` rows through the filtered list, clamped to
    /// the ends. A positive delta moves toward older items.
    func moveSelection(by delta: Int) {
        let items = filteredItems
        guard !items.isEmpty else { selectedID = nil; return }
        if let id = selectedID, let index = items.firstIndex(where: { $0.id == id }) {
            let next = min(max(index + delta, 0), items.count - 1)
            selectedID = items[next].id
        } else {
            selectedID = delta >= 0 ? items.first?.id : items.last?.id
        }
    }

    /// Copy the highlighted item to the pasteboard. Returns whether anything was
    /// activated, so the caller knows whether to dismiss the panel.
    @discardableResult
    func activateSelection() -> Bool {
        guard let id = selectedID,
              let item = filteredItems.first(where: { $0.id == id }) else { return false }
        copyToPasteboard(item.content)
        return true
    }

    private func selectFirst() {
        selectedID = filteredItems.first?.id
    }

    private func revalidateSelection() {
        let items = filteredItems
        if let id = selectedID, items.contains(where: { $0.id == id }) { return }
        selectedID = items.first?.id
    }
}
