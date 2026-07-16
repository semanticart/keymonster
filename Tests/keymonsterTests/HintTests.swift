import CoreGraphics
import XCTest
@testable import keymonster

final class HintLabelsTests: XCTestCase {
    func testLabelsAreDistinctTwoLetterPairs() {
        let labels = HintLabels.labels(count: 200)
        XCTAssertEqual(labels.count, 200)
        XCTAssertEqual(Set(labels).count, 200)
        XCTAssertTrue(labels.allSatisfy { $0.count == 2 })
    }

    func testHomeRowPairsComeFirst() {
        let homeRow = Set("asdfghjkl")
        // 9 home-row letters → 81 pure home-row pairs, and they must all come
        // before any pair touching another row.
        let labels = HintLabels.labels(count: 82)
        for label in labels.prefix(81) {
            XCTAssertTrue(label.allSatisfy { homeRow.contains($0) }, "\(label) should be home-row only")
        }
        XCTAssertFalse(labels[81].allSatisfy { homeRow.contains($0) })
    }

    func testCountIsCappedAtMaxCombinations() {
        XCTAssertEqual(HintLabels.labels(count: 10_000).count, HintLabels.maxCount)
        XCTAssertEqual(HintLabels.maxCount, 26 * 26)
    }

    func testZeroAndNegativeCounts() {
        XCTAssertTrue(HintLabels.labels(count: 0).isEmpty)
        XCTAssertTrue(HintLabels.labels(count: -1).isEmpty)
    }

    func testFewTargetsGetSingleLetterLabels() {
        let labels = HintLabels.labels(count: 5)
        XCTAssertEqual(labels.count, 5)
        XCTAssertEqual(Set(labels).count, 5)
        XCTAssertTrue(labels.allSatisfy { $0.count == 1 }, "few targets should resolve in one keystroke")
        // Home-row letters, cheapest first.
        XCTAssertEqual(labels, ["a", "s", "d", "f", "g"])
    }

    func testSingleLetterLabelsFillTheAlphabetBeforePairing() {
        // 26 targets still fit in one letter each; 27 tips over into pairs.
        XCTAssertTrue(HintLabels.labels(count: 26).allSatisfy { $0.count == 1 })
        XCTAssertTrue(HintLabels.labels(count: 27).allSatisfy { $0.count == 2 })
    }
}

final class HintSelectionTests: XCTestCase {
    private func selection(_ count: Int = 100) -> HintSelection {
        HintSelection(labels: HintLabels.labels(count: count))
    }

    func testTwoLettersResolveToAMatch() {
        var sel = selection()
        let labels = sel.labels
        guard case .pending(let matches) = sel.type(labels[5].first!) else {
            return XCTFail("first letter should be ambiguous")
        }
        XCTAssertGreaterThan(matches, 1)
        XCTAssertEqual(sel.type(labels[5].last!), .matched(index: 5))
    }

    func testUnknownPrefixIsRejectedAndNotRecorded() {
        // Enough labels to force two-letter pairs, so a first letter is a
        // non-terminal prefix rather than a whole label.
        var sel = selection(30)
        XCTAssertEqual(sel.type("z"), .rejected)
        XCTAssertEqual(sel.typed, "", "rejected letters must not advance the prefix")
        guard case .pending = sel.type("a") else {
            return XCTFail("'a' should be a prefix of several two-letter labels")
        }
        XCTAssertEqual(sel.typed, "a")
    }

    func testSingleLetterLabelResolvesInOneKeystroke() {
        // A handful of targets get one-letter labels: one press resolves it.
        var sel = selection(5)
        XCTAssertEqual(sel.type("a"), .matched(index: 0))
    }

    func testBackspaceUndoesALetter() {
        var sel = selection()
        _ = sel.type("a")
        XCTAssertEqual(sel.typed, "a")
        sel.backspace()
        XCTAssertEqual(sel.typed, "")
        sel.backspace() // extra backspaces are harmless
        XCTAssertEqual(sel.typed, "")
    }

    func testMatchIndexAlignsWithLabelOrder() {
        var sel = selection()
        let target = sel.labels[42]
        _ = sel.type(target.first!)
        XCTAssertEqual(sel.type(target.last!), .matched(index: 42))
    }
}

final class HintTargetFilterTests: XCTestCase {
    private let window = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testClickableByRole() {
        XCTAssertTrue(HintTargetFilter.isClickable(role: "AXButton", actions: []))
        XCTAssertTrue(HintTargetFilter.isClickable(role: "AXLink", actions: []))
        XCTAssertFalse(HintTargetFilter.isClickable(role: "AXGroup", actions: []))
        XCTAssertFalse(HintTargetFilter.isClickable(role: nil, actions: []))
    }

    func testClickableByActionEvenForGenericRoles() {
        // Web pages mark clickable <div>s as AXGroup with an AXPress action.
        XCTAssertTrue(HintTargetFilter.isClickable(role: "AXGroup", actions: ["AXPress"]))
        XCTAssertTrue(HintTargetFilter.isClickable(role: nil, actions: ["AXShowMenu"]))
        XCTAssertFalse(HintTargetFilter.isClickable(role: "AXGroup", actions: ["AXScrollToVisible"]))
    }

    func testVisibleRequiresOverlapWithWindow() {
        XCTAssertTrue(HintTargetFilter.isVisible(
            frame: CGRect(x: 200, y: 200, width: 40, height: 20), within: window
        ))
        // Scrolled out of the window entirely.
        XCTAssertFalse(HintTargetFilter.isVisible(
            frame: CGRect(x: 200, y: 900, width: 40, height: 20), within: window
        ))
    }

    func testTinyElementsAreSkipped() {
        XCTAssertFalse(HintTargetFilter.isVisible(
            frame: CGRect(x: 200, y: 200, width: 2, height: 2), within: window
        ))
    }

    func testWindowSizedContainersAreSkipped() {
        XCTAssertFalse(HintTargetFilter.isVisible(frame: window, within: window))
        // Nearly window-sized (a web area) is also a container...
        XCTAssertFalse(HintTargetFilter.isVisible(
            frame: window.insetBy(dx: 5, dy: 5), within: window
        ))
        // ...but a full-width toolbar of modest height is a real target zone.
        XCTAssertTrue(HintTargetFilter.isVisible(
            frame: CGRect(x: 100, y: 100, width: 800, height: 40), within: window
        ))
    }

    func testClickPointIsFrameCenter() {
        let target = HintTarget(frame: CGRect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertEqual(target.clickPoint, CGPoint(x: 25, y: 40))
    }
}

final class HintGeometryTests: XCTestCase {
    func testAXToCocoaFlipsVertically() {
        // A 100pt-tall window whose top edge is 50pt below the top of a 1000pt
        // primary screen sits 850pt above the Cocoa origin.
        let axRect = CGRect(x: 40, y: 50, width: 300, height: 100)
        let cocoa = HintGeometry.cocoaRect(fromAX: axRect, primaryScreenHeight: 1000)
        XCTAssertEqual(cocoa, CGRect(x: 40, y: 850, width: 300, height: 100))
    }

    func testRoundTripsThroughTheFlip() {
        let axRect = CGRect(x: 12, y: 34, width: 56, height: 78)
        let once = HintGeometry.cocoaRect(fromAX: axRect, primaryScreenHeight: 900)
        let twice = HintGeometry.cocoaRect(fromAX: once, primaryScreenHeight: 900)
        XCTAssertEqual(twice, axRect)
    }
}

final class HintShortcutSettingsTests: XCTestCase {
    @MainActor
    func testHintShortcutsPersistAcrossInstances() {
        let suite = "hint-settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.hintLeftShortcut = Shortcut(keyCode: 3, carbonModifiers: 0x0100)
        settings.hintRightShortcut = Shortcut(keyCode: 15, carbonModifiers: 0x0100 | 0x0200)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.hintLeftShortcut, Shortcut(keyCode: 3, carbonModifiers: 0x0100))
        XCTAssertEqual(reloaded.hintRightShortcut, Shortcut(keyCode: 15, carbonModifiers: 0x0100 | 0x0200))

        reloaded.hintLeftShortcut = nil
        let cleared = AppSettings(defaults: defaults)
        XCTAssertNil(cleared.hintLeftShortcut)
        XCTAssertNotNil(cleared.hintRightShortcut)
    }
}
