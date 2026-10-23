import Foundation

/// A printable cheat sheet of every shortcut, grouped the way the Settings tabs
/// group them. Built from the settings as plain values (no views, no AppKit) so
/// the grouping, the "unassigned" and conflict flags, and the pagination can all
/// be tested without rendering anything; ShortcutSheetPDF draws the result.
struct ShortcutSheet: Equatable {
    struct Entry: Equatable {
        let title: String
        /// One short line: what the shortcut does. Never wraps in the PDF, so
        /// keep it to roughly 70 characters.
        let detail: String
        /// The combo as separate keycaps (modifiers, then the key); nil when
        /// the feature has no shortcut yet.
        let keyCaps: [String]?
        /// The same combo is bound elsewhere too, so only one binding works.
        let isConflicting: Bool

        var isAssigned: Bool { keyCaps != nil }
    }

    struct Section: Equatable {
        let title: String
        let symbol: String
        let entries: [Entry]
        /// Shown in place of rows when the section has none (no apps or
        /// scripts configured yet).
        let emptyNote: String?
    }

    let sections: [Section]

    var allEntries: [Entry] { sections.flatMap(\.entries) }
    var assignedCount: Int { allEntries.filter(\.isAssigned).count }
    var unassignedCount: Int { allEntries.count - assignedCount }
    var conflictCount: Int { allEntries.filter(\.isConflicting).count }
}

extension Shortcut {
    /// Modifiers and the key as separate strings, for drawing keycaps. The
    /// formatter emits modifiers as single glyphs ahead of the key name.
    var keyCaps: [String] {
        let modifierGlyphs: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        let text = displayString
        let modifiers = text.prefix { modifierGlyphs.contains($0) }.map(String.init)
        let key = String(text.dropFirst(modifiers.count))
        return modifiers + (key.isEmpty ? [] : [key])
    }
}

/// The fields of AppSettings the sheet reads, so tests can build one directly.
struct ShortcutSheetInput {
    var clipboard: Shortcut?
    var appShortcuts: [AppShortcut]
    var hintLeft: Shortcut?
    var hintRight: Shortcut?
    var grid: Shortcut?
    var scroll: Shortcut?
    var textJump: Shortcut?
    var editInEditor: Shortcut?
    var menuSearch: Shortcut?
    var bookmarks: Shortcut?
    var dismissNotifications: Shortcut?
    var scripts: [ScriptShortcut]
}

extension ShortcutSheet {
    @MainActor
    init(settings: AppSettings) {
        self.init(ShortcutSheetInput(
            clipboard: settings.shortcut,
            appShortcuts: settings.appShortcuts,
            hintLeft: settings.hintLeftShortcut,
            hintRight: settings.hintRightShortcut,
            grid: settings.gridShortcut,
            scroll: settings.scrollShortcut,
            textJump: settings.textJumpShortcut,
            editInEditor: settings.editInEditorShortcut,
            menuSearch: settings.menuSearchShortcut,
            bookmarks: settings.bookmarksShortcut,
            dismissNotifications: settings.dismissNotificationsShortcut,
            scripts: settings.scriptShortcuts
        ))
    }

    init(_ input: ShortcutSheetInput) {
        let everyShortcut = [
            input.clipboard, input.hintLeft, input.hintRight, input.grid, input.scroll,
            input.textJump, input.editInEditor, input.menuSearch, input.bookmarks,
            input.dismissNotifications
        ].compactMap { $0 }
            + input.appShortcuts.filter { !$0.apps.isEmpty }.compactMap(\.shortcut)
            + input.scripts.filter { !$0.isEmpty }.compactMap(\.shortcut)
        let conflicts = ShortcutConflicts.conflicting(everyShortcut)

        func entry(_ title: String, _ detail: String, _ shortcut: Shortcut?) -> Entry {
            Entry(
                title: title,
                detail: detail,
                keyCaps: shortcut?.keyCaps,
                isConflicting: shortcut.map(conflicts.contains) ?? false
            )
        }

        let focusEntries = Self.focusEntries(input.appShortcuts, entry: entry)
        let scriptEntries = input.scripts.filter { !$0.isEmpty }.map {
            entry($0.displayName, $0.path, $0.shortcut)
        }

        sections = [
            Section(title: "Clipboard", symbol: "doc.on.clipboard", entries: [
                entry("Clipboard History", "Open history, type to filter, Return to paste", input.clipboard)
            ], emptyNote: nil),
            Section(title: "Focus", symbol: "macwindow.on.rectangle", entries: focusEntries,
                    emptyNote: "No app shortcuts yet — add one in Settings → Focus."),
            Section(title: "Mouse", symbol: "cursorarrow.rays", entries: [
                entry("Left Click Hints", "Label everything clickable; type a label to click", input.hintLeft),
                entry("Right Click Hints", "Same labels, right mouse button", input.hintRight),
                entry("Grid Click", "Zoom a keyboard-shaped grid; Return clicks the center", input.grid),
                entry("Scroll Panes", "Pick a pane, then J and K to scroll (Shift for 4× faster)", input.scroll)
            ], emptyNote: nil),
            Section(title: "Text", symbol: "character.cursor.ibeam", entries: [
                entry("Text Jump", "Press, type a character, then a label to move the caret", input.textJump),
                entry("Edit in Editor", "Open the focused text field in your own editor", input.editInEditor)
            ], emptyNote: nil),
            Section(title: "Menus", symbol: "filemenu.and.selection", entries: [
                entry("Search Menus", "Fuzzy-find and run any menu item in the active app", input.menuSearch)
            ], emptyNote: nil),
            Section(title: "Bookmarks", symbol: "bookmark", entries: [
                entry("Search Bookmarks", "Fuzzy-find and open a site, file, or folder", input.bookmarks)
            ], emptyNote: nil),
            Section(title: "Notifications", symbol: "bell.slash", entries: [
                entry("Dismiss Notifications", "Clear every notification banner on screen", input.dismissNotifications)
            ], emptyNote: nil),
            Section(title: "Scripts", symbol: "terminal", entries: scriptEntries,
                    emptyNote: "No scripts yet — add one in Settings → Scripts.")
        ]
    }

    private static func focusEntries(
        _ bindings: [AppShortcut],
        entry: (String, String, Shortcut?) -> Entry
    ) -> [Entry] {
        bindings.filter { !$0.apps.isEmpty }.map { binding in
            entry(
                binding.apps.map(\.name).joined(separator: " → "),
                binding.apps.count > 1
                    ? "Focus the first; press again to cycle"
                    : "Focus the app, launching it if needed",
                binding.shortcut
            )
        }
    }
}

// MARK: - Pagination

/// Where each row of the sheet lands on which page. Every row has a fixed
/// height (details are single-line), so paging is plain arithmetic rather than
/// measuring views.
enum ShortcutSheetLayout {
    static let pageSize = CGSize(width: 612, height: 792) // US Letter, points
    static let margin: CGFloat = 44
    static let footerHeight: CGFloat = 34
    static let titleBlockHeight: CGFloat = 104
    static let sectionGap: CGFloat = 20
    static let sectionHeaderHeight: CGFloat = 34
    static let rowHeight: CGFloat = 42

    enum Item: Equatable {
        /// `continued` marks a section resuming on a new page.
        case header(ShortcutSheet.Section, continued: Bool)
        case row(ShortcutSheet.Entry)
        case emptyNote(String)
    }

    struct Page: Equatable {
        var items: [Item] = []
        var isFirst = false
    }

    /// Room on a page for items (below the title block on the first page).
    static func contentHeight(firstPage: Bool) -> CGFloat {
        pageSize.height - margin * 2 - footerHeight - (firstPage ? titleBlockHeight : 0)
    }

    static func height(of item: Item, atTop: Bool) -> CGFloat {
        switch item {
        case .header: return sectionHeaderHeight + (atTop ? 0 : sectionGap)
        case .row, .emptyNote: return rowHeight
        }
    }

    static func paginate(_ sheet: ShortcutSheet) -> [Page] {
        var pages = [Page(isFirst: true)]
        var used: CGFloat = 0

        func remaining() -> CGFloat {
            contentHeight(firstPage: pages.count == 1) - used
        }
        func startPage() {
            pages.append(Page())
            used = 0
        }
        func place(_ item: Item) {
            used += height(of: item, atTop: pages[pages.count - 1].items.isEmpty)
            pages[pages.count - 1].items.append(item)
        }

        for section in sheet.sections {
            var body: [Item] = section.entries.map(Item.row)
            if body.isEmpty, let note = section.emptyNote { body = [.emptyNote(note)] }

            var continued = false
            while !body.isEmpty {
                let header = Item.header(section, continued: continued)
                // A header never sits alone at the foot of a page: it needs its
                // first row below it, or both move to the next page.
                let atTop = pages[pages.count - 1].items.isEmpty
                let needed = height(of: header, atTop: atTop) + height(of: body[0], atTop: false)
                if needed > remaining() { startPage() }
                place(header)
                while let next = body.first, height(of: next, atTop: false) <= remaining() {
                    place(next)
                    body.removeFirst()
                }
                continued = true
                if !body.isEmpty { startPage() }
            }
        }
        return pages
    }
}
