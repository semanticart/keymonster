import XCTest
@testable import keymonster

@MainActor
final class ShortcutSheetTests: XCTestCase {
    private let cmdShiftV = Shortcut(keyCode: 9, carbonModifiers: CarbonModifierMask.command | CarbonModifierMask.shift)
    private let ctrlJ = Shortcut(keyCode: 38, carbonModifiers: CarbonModifierMask.control)

    private func input(
        clipboard: Shortcut? = nil,
        apps: [AppShortcut] = [],
        grid: Shortcut? = nil,
        dismissNotifications: Shortcut? = nil,
        scripts: [ScriptShortcut] = []
    ) -> ShortcutSheetInput {
        ShortcutSheetInput(
            clipboard: clipboard, appShortcuts: apps, hintLeft: nil, hintRight: nil, grid: grid,
            scroll: nil, textJump: nil, editInEditor: nil, menuSearch: nil, bookmarks: nil,
            dismissNotifications: dismissNotifications, scripts: scripts
        )
    }

    private func entry(_ title: String, in sheet: ShortcutSheet) -> ShortcutSheet.Entry? {
        sheet.allEntries.first { $0.title == title }
    }

    func testKeyCapsSplitModifiersFromKey() {
        XCTAssertEqual(cmdShiftV.keyCaps, ["⇧", "⌘", "V"])
        XCTAssertEqual(Shortcut(keyCode: 49, carbonModifiers: CarbonModifierMask.option).keyCaps, ["⌥", "Space"])
    }

    func testUnassignedFeaturesAreListedAndFlagged() {
        let sheet = ShortcutSheet(input(clipboard: cmdShiftV))
        XCTAssertEqual(entry("Clipboard History", in: sheet)?.keyCaps, ["⇧", "⌘", "V"])
        XCTAssertEqual(entry("Grid Click", in: sheet)?.isAssigned, false)
        XCTAssertEqual(sheet.assignedCount, 1)
        XCTAssertEqual(sheet.unassignedCount, sheet.allEntries.count - 1)
    }

    func testDismissNotificationsIsListedAndConflictsAreFlagged() {
        let unassigned = ShortcutSheet(input())
        XCTAssertEqual(entry("Dismiss Notifications", in: unassigned)?.isAssigned, false)

        let assigned = ShortcutSheet(input(dismissNotifications: ctrlJ))
        XCTAssertEqual(entry("Dismiss Notifications", in: assigned)?.keyCaps, ["⌃", "J"])

        let clashing = ShortcutSheet(input(grid: ctrlJ, dismissNotifications: ctrlJ))
        XCTAssertEqual(entry("Dismiss Notifications", in: clashing)?.isConflicting, true)
        XCTAssertEqual(entry("Grid Click", in: clashing)?.isConflicting, true)
    }

    func testFocusEntriesNameTheirAppsAndEmptyOnesAreOmitted() {
        let slack = AppRef(bundleID: "a", name: "Slack")
        let chrome = AppRef(bundleID: "b", name: "Chrome")
        let sheet = ShortcutSheet(input(apps: [
            AppShortcut(shortcut: ctrlJ, apps: [slack, chrome]),
            AppShortcut(shortcut: nil, apps: [])
        ]))
        let focus = sheet.sections.first { $0.title == "Focus" }
        XCTAssertEqual(focus?.entries.map(\.title), ["Slack → Chrome"])
    }

    func testScriptsWithoutAPathAreOmitted() {
        let sheet = ShortcutSheet(input(scripts: [
            ScriptShortcut(shortcut: ctrlJ, path: "/Users/me/bin/deploy.sh"),
            ScriptShortcut(shortcut: nil, path: "")
        ]))
        let scripts = sheet.sections.first { $0.title == "Scripts" }
        XCTAssertEqual(scripts?.entries.map(\.title), ["deploy.sh"])
    }

    func testDuplicateComboIsFlaggedOnBothEntries() {
        let sheet = ShortcutSheet(input(clipboard: ctrlJ, grid: ctrlJ))
        XCTAssertEqual(sheet.conflictCount, 2)
        XCTAssertEqual(entry("Grid Click", in: sheet)?.isConflicting, true)
    }

    func testPaginationKeepsEveryRowAndNeverStrandsAHeader() {
        let scripts = (0..<40).map { ScriptShortcut(shortcut: nil, path: "/s/script\($0).sh") }
        let sheet = ShortcutSheet(input(scripts: scripts))
        let pages = ShortcutSheetLayout.paginate(sheet)
        XCTAssertGreaterThan(pages.count, 1)

        var rows = 0
        for (index, page) in pages.enumerated() {
            rows += page.items.filter { if case .row = $0 { return true } else { return false } }.count
            var used: CGFloat = 0
            for (position, item) in page.items.enumerated() {
                used += ShortcutSheetLayout.height(of: item, atTop: position == 0)
            }
            XCTAssertLessThanOrEqual(used, ShortcutSheetLayout.contentHeight(firstPage: index == 0))
            if case .header = page.items.last { XCTFail("header stranded at the end of page \(index)") }
        }
        XCTAssertEqual(rows, sheet.allEntries.count)
        // 40 script rows can't fit one page, so the section must resume with a
        // "continued" header rather than bare rows.
        let resumed = pages.dropFirst().contains {
            if case .header(_, continued: true) = $0.items.first { return true } else { return false }
        }
        XCTAssertTrue(resumed)
    }

    func testRendersAMultiPagePDF() throws {
        let scripts = (0..<30).map { ScriptShortcut(shortcut: ctrlJ, path: "/Users/me/bin/script\($0).sh") }
        var sample = input(clipboard: cmdShiftV, grid: ctrlJ, scripts: scripts)
        let apps = [AppRef(bundleID: "a", name: "Slack"), AppRef(bundleID: "b", name: "Chrome")]
        sample.appShortcuts = [AppShortcut(shortcut: ctrlJ, apps: apps)]
        let data = try XCTUnwrap(ShortcutSheetPDF.data(for: ShortcutSheet(sample)))
        XCTAssertEqual(String(data: data.prefix(5), encoding: .ascii), "%PDF-")
        if let out = ProcessInfo.processInfo.environment["SHORTCUT_SHEET_OUT"] {
            try data.write(to: URL(fileURLWithPath: out))
        }
    }
}
