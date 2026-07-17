import Foundation

/// Drives the menu-finder panel's search-first interaction: it holds the scanned
/// items and the query, derives the fuzzy-ranked list, and tracks the keyboard
/// selection so the panel can move it (Ctrl-N/Ctrl-P, arrows) and run it (Return).
/// Kept AppKit-free — the controller owns the pressable AX elements.
@MainActor
final class MenuFinderViewModel: ObservableObject {
    /// The current query. Editing it re-selects the best match.
    @Published var searchText: String = "" {
        didSet { selectFirst() }
    }

    /// The id of the keyboard-highlighted row, if any.
    @Published var selectedID: Int?

    /// Every actionable menu item for the active app, in menu order.
    @Published private(set) var items: [MenuBarItem] = []

    /// Name of the app whose menus are shown, for the panel header.
    @Published private(set) var appName: String = ""

    /// Bumped each time the panel is presented so the view can refocus the field.
    @Published private(set) var focusBump = 0

    /// The items matching the query, best match first (or all, in order).
    var filteredItems: [MenuBarItem] {
        MenuItemFilter.filter(items, query: searchText)
    }

    var selectedItem: MenuBarItem? {
        guard let selectedID else { return nil }
        return filteredItems.first { $0.id == selectedID }
    }

    /// Load a fresh scan and reset to a blank query with the first item selected.
    /// Call each time the panel is shown.
    func present(items: [MenuBarItem], appName: String) {
        self.items = items
        self.appName = appName
        searchText = ""
        selectFirst()
        focusBump &+= 1
    }

    /// Move the highlight by `delta` rows through the filtered list, clamped to
    /// the ends (positive = down).
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

    /// The highlighted item to run, or nil if nothing is selected. The caller
    /// looks up its AX element and presses it.
    func activateSelection() -> MenuBarItem? {
        selectedItem
    }

    private func selectFirst() {
        selectedID = filteredItems.first?.id
    }
}
