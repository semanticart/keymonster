import XCTest
@testable import keymonster

final class ScrollActivationTests: XCTestCase {
    func testNoPanesNeverStartsTheMode() {
        XCTAssertEqual(ScrollActivation.forPaneCount(0), .none)
    }

    func testLonePaneScrollsImmediately() {
        XCTAssertEqual(ScrollActivation.forPaneCount(1), .scroll(index: 0))
    }

    func testSeveralPanesWaitForAPick() {
        XCTAssertEqual(ScrollActivation.forPaneCount(2), .select)
        XCTAssertEqual(ScrollActivation.forPaneCount(9), .select)
    }
}

final class ScrollWheelTests: XCTestCase {
    func testJScrollsDownAndKScrollsUp() {
        // CGEvent's wheel axis is positive-up: j (down) is negative, k positive.
        XCTAssertEqual(ScrollWheel.pixels(for: "j"), -ScrollWheel.pixelStep)
        XCTAssertEqual(ScrollWheel.pixels(for: "k"), ScrollWheel.pixelStep)
    }

    func testOtherKeysDoNotScroll() {
        XCTAssertNil(ScrollWheel.pixels(for: "h"))
        XCTAssertNil(ScrollWheel.pixels(for: "l"))
        XCTAssertNil(ScrollWheel.pixels(for: " "))
    }
}

final class ScrollPaneFilterTests: XCTestCase {
    func testNativeAndWebContainerRolesCountAsPanes() {
        // AXScrollArea is the native scroller; the rest are how Electron apps
        // (with no scroll areas at all) model their scrollable regions —
        // Slack's content root is a web area and its channel sidebar an
        // outline.
        for role in ["AXScrollArea", "AXWebArea", "AXOutline", "AXList", "AXTable", "AXTextArea"] {
            XCTAssertTrue(ScrollPaneFilter.paneRoles.contains(role), role)
        }
        XCTAssertFalse(ScrollPaneFilter.paneRoles.contains("AXGroup"))
        XCTAssertFalse(ScrollPaneFilter.paneRoles.contains("AXButton"))
    }

    func testScrollBarStateOverrulesGeometry() {
        let pane = CGRect(x: 0, y: 0, width: 500, height: 400)
        // An empty text view fills its viewport, so geometry alone would say
        // scrollable — the disabled scroll bar knows better.
        let filling = pane
        XCTAssertFalse(ScrollPaneFilter.isScrollable(barEnabled: false, content: filling, pane: pane))
        // And an enabled bar wins even when the materialized content looks
        // short.
        let short = CGRect(x: 0, y: 0, width: 500, height: 100)
        XCTAssertTrue(ScrollPaneFilter.isScrollable(barEnabled: true, content: short, pane: pane))
    }

    func testWithoutAScrollBarGeometryDecides() {
        let pane = CGRect(x: 0, y: 0, width: 500, height: 400)
        let short = CGRect(x: 0, y: 0, width: 500, height: 100)
        XCTAssertFalse(ScrollPaneFilter.isScrollable(barEnabled: nil, content: short, pane: pane))
        XCTAssertTrue(ScrollPaneFilter.isScrollable(barEnabled: nil, content: pane, pane: pane))
    }

    func testContentFallingShortOfThePaneCannotScroll() {
        // A sidebar with a handful of channels: rows stop far above the pane's
        // bottom edge, so there's nothing to scroll and no badge to offer.
        let pane = CGRect(x: 0, y: 100, width: 280, height: 544)
        let fewRows = CGRect(x: 0, y: 106, width: 280, height: 200)
        XCTAssertFalse(ScrollPaneFilter.hasScrollableContent(fewRows, pane: pane))
    }

    func testContentFillingOrOverflowingThePaneCanScroll() {
        let pane = CGRect(x: 0, y: 100, width: 280, height: 544)
        // A virtualized list only materializes on-screen rows, so "full" is
        // as scrollable as it gets…
        let filling = CGRect(x: 0, y: 106, width: 280, height: 536)
        XCTAssertTrue(ScrollPaneFilter.hasScrollableContent(filling, pane: pane))
        // …and a native document view taller than its viewport certainly is.
        let overflowing = CGRect(x: 0, y: 100, width: 280, height: 2000)
        XCTAssertTrue(ScrollPaneFilter.hasScrollableContent(overflowing, pane: pane))
    }

    func testRestingListGetsARowOfSlack() {
        // Scrolled to the top, a list often rests with its last row a bit shy
        // of the bottom edge; that's still a scrollable pane.
        let pane = CGRect(x: 0, y: 100, width: 280, height: 544)
        let resting = CGRect(x: 0, y: 100, width: 280, height: 544 - ScrollPaneFilter.restingGapAllowance)
        XCTAssertTrue(ScrollPaneFilter.hasScrollableContent(resting, pane: pane))
    }

    func testUnmeasurableContentGetsTheBenefitOfTheDoubt() {
        let pane = CGRect(x: 0, y: 100, width: 280, height: 544)
        XCTAssertTrue(ScrollPaneFilter.hasScrollableContent(.null, pane: pane))
        XCTAssertTrue(ScrollPaneFilter.hasScrollableContent(.zero, pane: pane))
    }

    func testOutlineFillingItsScrollAreaIsRedundant() {
        // A native outline occupies (nearly) its whole enclosing scroll area:
        // one scroller, seen twice — only the outer one gets a badge.
        let scrollArea = CGRect(x: 0, y: 0, width: 300, height: 500)
        XCTAssertTrue(ScrollPaneFilter.isRedundant(
            visible: scrollArea.insetBy(dx: 8, dy: 8), withinAncestor: scrollArea
        ))
        XCTAssertTrue(ScrollPaneFilter.isRedundant(visible: scrollArea, withinAncestor: scrollArea))
    }

    func testDistinctSubPaneIsNotRedundant() {
        // Slack's channel sidebar covers a sliver of the full-window web area;
        // both deserve badges.
        let webArea = CGRect(x: 0, y: 0, width: 1309, height: 800)
        let sidebar = CGRect(x: 130, y: 180, width: 281, height: 544)
        XCTAssertFalse(ScrollPaneFilter.isRedundant(visible: sidebar, withinAncestor: webArea))
    }

    func testRoomyPanesAreUsable() {
        XCTAssertTrue(
            ScrollPaneFilter.isUsable(visible: CGRect(x: 0, y: 0, width: 400, height: 300))
        )
    }

    func testSliversAreNot() {
        // A pane scrolled almost entirely off the window, or a scroll-bar-thin
        // strip, has no room for a badge and nothing worth scrolling.
        XCTAssertFalse(
            ScrollPaneFilter.isUsable(visible: CGRect(x: 0, y: 0, width: 400, height: 10))
        )
        XCTAssertFalse(
            ScrollPaneFilter.isUsable(visible: CGRect(x: 0, y: 0, width: 16, height: 300))
        )
        // A null intersection means the pane isn't on the window at all.
        XCTAssertFalse(ScrollPaneFilter.isUsable(visible: .null))
    }
}
