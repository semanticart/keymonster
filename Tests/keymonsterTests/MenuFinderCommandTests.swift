import XCTest
@testable import keymonster

final class MenuFinderCommandTests: XCTestCase {
    func testEscapeDismisses() {
        XCTAssertEqual(MenuFinderCommand.from(keyCode: 53, control: false), .dismiss)
        XCTAssertEqual(MenuFinderCommand.from(keyCode: 53, control: true), .dismiss)
    }

    func testArrowsMoveTheSelectionWithoutControl() {
        XCTAssertEqual(MenuFinderCommand.from(keyCode: 125, control: false), .moveSelection(1))
        XCTAssertEqual(MenuFinderCommand.from(keyCode: 126, control: false), .moveSelection(-1))
    }

    func testCtrlNAndCtrlPMoveTheSelection() {
        XCTAssertEqual(MenuFinderCommand.from(keyCode: 45, control: true), .moveSelection(1))
        XCTAssertEqual(MenuFinderCommand.from(keyCode: 35, control: true), .moveSelection(-1))
    }

    /// Plain N and P are ordinary typing and must reach the search field.
    func testPlainLettersPassThroughToTheSearchField() {
        XCTAssertNil(MenuFinderCommand.from(keyCode: 45, control: false))
        XCTAssertNil(MenuFinderCommand.from(keyCode: 35, control: false))
    }

    func testReturnAndKeypadEnterActivate() {
        XCTAssertEqual(MenuFinderCommand.from(keyCode: 36, control: false), .activate)
        XCTAssertEqual(MenuFinderCommand.from(keyCode: 76, control: false), .activate)
    }
}
