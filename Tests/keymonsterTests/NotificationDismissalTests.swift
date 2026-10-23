import XCTest
@testable import keymonster

/// A hand-built Notification Center tree. The action strings and subrole are
/// copied from a live dump of macOS 26's banner, where `Close` arrives as the
/// custom action `Name:Close\nTarget:0x0\nSelector:(null)`.
private final class FakeTree: NotificationTree {
    final class Node {
        let subrole: String?
        let actions: [String]
        let children: [Node]
        init(_ subrole: String? = nil, actions: [String] = [], _ children: [Node] = []) {
            self.subrole = subrole
            self.actions = actions
            self.children = children
        }
    }

    var performed: [(action: String, node: Node)] = []
    var failing: Set<String> = []

    func children(of element: Node) -> [Node] { element.children }
    func subrole(of element: Node) -> String? { element.subrole }
    func actionNames(of element: Node) -> [String] { element.actions }
    func perform(_ action: String, on element: Node) -> Bool {
        performed.append((action, element))
        return !failing.contains(action)
    }
}

private enum Live {
    static let banner = "AXNotificationCenterBanner"
    static let show = "Name:Show\nTarget:0x0\nSelector:(null)"
    static let details = "Name:Show Details\nTarget:0x0\nSelector:(null)"
    static let close = "Name:Close\nTarget:0x0\nSelector:(null)"
    static let clearAll = "Name:Clear All\nTarget:0x0\nSelector:(null)"
}

final class NotificationDismissalTests: XCTestCase {
    private typealias Node = FakeTree.Node

    private func banner(extra: [String] = []) -> Node {
        Node(Live.banner, actions: ["AXPress", Live.details, Live.show, Live.close] + extra,
             [Node("AXStaticText")])
    }

    private func pick(_ actions: [String], names: DismissNames = .english) -> String? {
        NotificationDismissal.dismissAction(in: actions, names: names)
    }

    private func dismissAll(_ tree: FakeTree, _ roots: [Node]) -> Int {
        NotificationDismissal.dismissAll(in: tree, roots: roots, names: .english)
    }

    // MARK: action choice

    func testDisplayNameReadsCustomActionNames() {
        XCTAssertEqual(NotificationDismissal.displayName(of: Live.close), "Close")
        XCTAssertEqual(NotificationDismissal.displayName(of: "Name:Show Details|Target:0x0"), "Show Details")
        XCTAssertNil(NotificationDismissal.displayName(of: "AXPress"))
    }

    func testPicksCloseFromTheLiveBannerActions() {
        let actions = ["AXPress", Live.details, Live.show, Live.close]
        XCTAssertEqual(pick(actions), Live.close)
    }

    func testTakesTheLastActionNotTheMostPreferredName() {
        // Position decides: the system verb is always last.
        XCTAssertEqual(pick([Live.clearAll, Live.close]), Live.close)
        XCTAssertEqual(pick([Live.close, Live.clearAll]), Live.clearAll)
    }

    func testAnAppsOwnCloseActionIsNeverMistakenForTheSystemOne() {
        // Live shape with app actions: AXPress, Show Details, <app actions…>, Close.
        let appClose = "Name:Close\nTarget:0x0\nSelector:(null)"
        let actions = ["AXPress", Live.details, appClose, "Name:Reply\nTarget:0x0", "Name:Snooze\nTarget:0x0"]
        XCTAssertNil(pick(actions),
                     "last action is Snooze, which isn't a dismiss verb")
        XCTAssertEqual(pick(actions + [Live.close]), Live.close)
    }

    func testFindsTheLastActionAmongCustomActionsWithoutRelyingOnEnglish() {
        let german = ["AXPress", "Name:Details einblenden\nTarget:0x0",
                      "Name:Antworten\nTarget:0x0", "Name:Schließen\nTarget:0x0"]
        let names = DismissNames(["Close", "Clear All", "Schließen"])
        XCTAssertEqual(pick(german, names: names), german.last)
        XCTAssertNil(pick(german))
    }

    func testTrailingNonCustomActionIsSkippedWhenFindingTheLast() {
        XCTAssertEqual(pick([Live.close, "AXShowMenu"]), Live.close)
    }

    // MARK: localized names

    func testLocalizedNamesComeFromEveryLanguageTableAndIncludeEnglish() {
        let tables: [String: Any] = [
            "de": ["Close": "Schließen", "Clear All": "Alle entfernen", "Unrelated": "x"],
            "ja": ["Close": "閉じる", "Clear": "消去"],
            "bad": "not a table"
        ]
        let names = DismissNames.localized(fromTables: tables)
        for name in ["Close", "Clear All", "schließen", "Alle entfernen", "閉じる", "消去"] {
            XCTAssertTrue(names.contains(name), name)
        }
        XCTAssertFalse(names.contains("Unrelated"))
        XCTAssertFalse(names.contains("x"))
    }

    func testNameMatchIgnoresCaseAndSurroundingSpace() {
        XCTAssertTrue(DismissNames.english.contains(" CLOSE\n"))
        XCTAssertFalse(DismissNames.english.contains("Closet"))
    }

    func testMissingOrCorruptLoctableFallsBackToEnglish() throws {
        let missing = URL(fileURLWithPath: "/nonexistent/Localizable.loctable")
        XCTAssertTrue(DismissNames.localized(from: missing).contains("Clear All"))

        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("junk-\(UUID()).loctable")
        try Data("not a plist".utf8).write(to: junk)
        defer { try? FileManager.default.removeItem(at: junk) }
        let names = DismissNames.localized(from: junk)
        XCTAssertTrue(names.contains("Close"))
        XCTAssertFalse(names.contains("Schließen"))
    }

    func testReadsAPlistLoctableFromDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ok-\(UUID()).loctable")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["fr": ["Close": "Fermer"]], format: .binary, options: 0)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(DismissNames.localized(from: url).contains("Fermer"))
    }

    func testSystemLoctableCoversTheTranslationsWeNeedWhenPresent() throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: DismissNames.loctableURL.path),
                          "no Notification Center loctable on this macOS")
        let names = DismissNames.localized()
        // Seen on macOS 26.6.2; if Apple reshapes the file this fails loudly
        // instead of silently dropping every non-English locale.
        for name in ["Schließen", "Alle entfernen", "閉じる", "すべて消去"] {
            XCTAssertTrue(names.contains(name), name)
        }
    }

    func testClearIsAFallback() {
        XCTAssertEqual(pick(["Name:Clear\nTarget:0x0"]), "Name:Clear\nTarget:0x0")
    }

    func testNeverPicksShowOrPress() {
        XCTAssertNil(pick(["AXPress", Live.details, Live.show]))
        XCTAssertNil(pick([]))
    }

    func testDoesNotMatchLookalikeNames() {
        XCTAssertNil(pick(["Name:Closet\nTarget:0x0", "Name:Close Tab"]))
    }

    func testMatchingIgnoresCase() {
        XCTAssertEqual(pick(["Name:CLOSE"]), "Name:CLOSE")
    }

    // MARK: tree walk

    func testDismissesTheLiveShapedBanner() {
        let target = banner()
        let root = Node("AXSystemDialog", [Node("AXHostingView", [Node(nil, [Node(nil, [target])])])])
        let tree = FakeTree()

        XCTAssertEqual(dismissAll(tree, [root]), 1)
        XCTAssertEqual(tree.performed.count, 1)
        XCTAssertTrue(tree.performed[0].node === target)
        XCTAssertEqual(tree.performed[0].action, Live.close)
    }

    func testDismissesEveryVisibleBanner() {
        let first = banner(), second = banner()
        let tree = FakeTree()

        let count = dismissAll(tree, [Node(nil, [first, second])])

        XCTAssertEqual(count, 2)
        XCTAssertTrue(tree.performed[0].node === first, "document order is preserved")
        XCTAssertTrue(tree.performed[1].node === second)
    }

    func testSearchesEveryRootWindow() {
        let tree = FakeTree()
        let count = dismissAll(tree, [Node(nil, [banner()]), Node(nil, [banner()])])
        XCTAssertEqual(count, 2)
    }

    func testDoesNothingWhenThereAreNoNotifications() {
        let tree = FakeTree()
        let empty = Node("AXSystemDialog", [Node("AXHostingView", [Node(nil, [Node(nil)])])])

        XCTAssertEqual(dismissAll(tree, [empty]), 0)
        XCTAssertEqual(dismissAll(tree, []), 0)
        XCTAssertTrue(tree.performed.isEmpty)
    }

    func testStackIsClearedOnceWithoutTouchingItsInnerBanners() {
        let inner = banner()
        let stack = Node("AXNotificationCenterAlertStack",
                         actions: ["AXPress", Live.show, Live.clearAll], [inner, banner()])
        let tree = FakeTree()

        XCTAssertEqual(dismissAll(tree, [Node(nil, [stack])]), 1)
        XCTAssertTrue(tree.performed[0].node === stack)
        XCTAssertEqual(tree.performed[0].action, Live.clearAll)
    }

    func testClearsEveryStackInTheRecordedNotificationCenterPanel() {
        // Shape and action sets captured from the open Notification Center on
        // macOS 26: a scroll area holding one group of stacks, then the
        // "Edit Widgets" / "Clear Notifications…" controls, which aren't notifications.
        let stackA = Node("AXNotificationCenterBannerStack",
                          actions: ["AXPress", Live.details, Live.show, Live.clearAll],
                          [Node("AXStaticText"), Node("AXStaticText")])
        let stackB = Node("AXNotificationCenterBannerStack",
                          actions: ["AXPress", Live.details, Live.clearAll],
                          [Node("AXStaticText"), Node("AXStaticText"), Node("AXStaticText")])
        let panel = Node("AXSystemDialog", [Node("AXHostingView", [Node(nil, [Node(nil, [
            Node(nil, [stackA, stackB]),
            Node("AXButton", actions: ["AXPress"]),
            Node("AXMenuButton", actions: ["AXShowMenu"])
        ])])])])
        let tree = FakeTree()

        XCTAssertEqual(dismissAll(tree, [panel]), 2)
        XCTAssertEqual(tree.performed.map(\.action), [Live.clearAll, Live.clearAll])
        XCTAssertTrue(tree.performed[0].node === stackA)
        XCTAssertTrue(tree.performed[1].node === stackB)
    }

    func testTargetsFindsWithoutPressing() {
        let tree = FakeTree()
        let found = NotificationDismissal.targets(in: tree, roots: [Node(nil, [banner()])], names: .english)
        XCTAssertEqual(found.map(\.action), [Live.close])
        XCTAssertTrue(tree.performed.isEmpty)
    }

    func testIgnoresUnrelatedElementsThatHappenToOfferClose() {
        // A window's close button is not a notification, whatever it's called.
        let closeButton = Node("AXCloseButton", actions: ["AXPress", Live.close])
        let plainGroup = Node(nil, actions: [Live.close])
        let tree = FakeTree()

        XCTAssertEqual(dismissAll(tree, [Node(nil, [closeButton, plainGroup])]), 0)
        XCTAssertTrue(tree.performed.isEmpty)
    }

    func testNotificationWithoutADismissActionIsDescendedInto() {
        // E.g. a container carrying the subrole but no verbs: banners inside still count.
        let container = Node(Live.banner, actions: ["AXPress"], [banner()])
        let tree = FakeTree()
        XCTAssertEqual(dismissAll(tree, [container]), 1)
    }

    func testCountsOnlySuccessfulPresses() {
        let tree = FakeTree()
        tree.failing = [Live.close]
        let root = Node(nil, [banner(), Node(Live.banner, actions: [Live.clearAll])])

        XCTAssertEqual(dismissAll(tree, [root]), 1)
        XCTAssertEqual(tree.performed.count, 2, "a failed press doesn't stop the rest")
    }

    func testTargetsAreCollectedBeforeAnyIsPressed() {
        // Pressing animates the real tree; the walk must be finished by then.
        final class OrderTree: NotificationTree {
            var log: [String] = []
            func children(of element: Int) -> [Int] { log.append("walk\(element)"); return element == 0 ? [1, 2] : [] }
            func subrole(of element: Int) -> String? { element == 0 ? nil : "AXNotificationCenterBanner" }
            func actionNames(of element: Int) -> [String] { ["Name:Close"] }
            func perform(_ action: String, on element: Int) -> Bool { log.append("press\(element)"); return true }
        }
        let tree = OrderTree()
        XCTAssertEqual(NotificationDismissal.dismissAll(in: tree, roots: [0], names: .english), 2)
        XCTAssertEqual(tree.log, ["walk0", "press1", "press2"])
    }
}
