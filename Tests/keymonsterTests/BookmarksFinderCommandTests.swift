import XCTest
@testable import keymonster

final class BookmarksFinderCommandTests: XCTestCase {
    func testEscapeDismisses() {
        XCTAssertEqual(BookmarksFinderCommand.from(keyCode: 53, control: false), .dismiss)
        XCTAssertEqual(BookmarksFinderCommand.from(keyCode: 53, control: true), .dismiss)
    }

    func testArrowsMoveTheSelectionWithoutControl() {
        XCTAssertEqual(BookmarksFinderCommand.from(keyCode: 125, control: false), .moveSelection(1))
        XCTAssertEqual(BookmarksFinderCommand.from(keyCode: 126, control: false), .moveSelection(-1))
    }

    func testCtrlNAndCtrlPMoveTheSelection() {
        XCTAssertEqual(BookmarksFinderCommand.from(keyCode: 45, control: true), .moveSelection(1))
        XCTAssertEqual(BookmarksFinderCommand.from(keyCode: 35, control: true), .moveSelection(-1))
    }

    /// Plain N and P are ordinary typing and must reach the search field.
    func testPlainLettersPassThroughToTheSearchField() {
        XCTAssertNil(BookmarksFinderCommand.from(keyCode: 45, control: false))
        XCTAssertNil(BookmarksFinderCommand.from(keyCode: 35, control: false))
    }

    func testReturnAndKeypadEnterActivate() {
        XCTAssertEqual(BookmarksFinderCommand.from(keyCode: 36, control: false), .activate)
        XCTAssertEqual(BookmarksFinderCommand.from(keyCode: 76, control: false), .activate)
    }
}
