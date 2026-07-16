import XCTest
@testable import keymonster

final class PanelCommandTests: XCTestCase {
    func testEscapeDismisses() {
        XCTAssertEqual(PanelCommand.from(keyCode: 53, control: false), .dismiss)
        XCTAssertEqual(PanelCommand.from(keyCode: 53, control: true), .dismiss)
    }

    func testArrowsMoveTheSelectionWithoutControl() {
        XCTAssertEqual(PanelCommand.from(keyCode: 125, control: false), .moveSelection(1))
        XCTAssertEqual(PanelCommand.from(keyCode: 126, control: false), .moveSelection(-1))
    }

    func testCtrlNAndCtrlPMoveTheSelection() {
        XCTAssertEqual(PanelCommand.from(keyCode: 45, control: true), .moveSelection(1))
        XCTAssertEqual(PanelCommand.from(keyCode: 35, control: true), .moveSelection(-1))
    }

    /// Plain N and P must reach the search field — they're ordinary typing.
    func testPlainLettersPassThroughToTheSearchField() {
        XCTAssertNil(PanelCommand.from(keyCode: 45, control: false))
        XCTAssertNil(PanelCommand.from(keyCode: 35, control: false))
        XCTAssertNil(PanelCommand.from(keyCode: 38, control: false))
        XCTAssertNil(PanelCommand.from(keyCode: 40, control: false))
    }

    func testCtrlJAndCtrlKScrollTheDetailPane() {
        XCTAssertEqual(PanelCommand.from(keyCode: 38, control: true), .scrollDetail(1))
        XCTAssertEqual(PanelCommand.from(keyCode: 40, control: true), .scrollDetail(-1))
    }

    func testReturnAndKeypadEnterActivate() {
        XCTAssertEqual(PanelCommand.from(keyCode: 36, control: false), .activate)
        XCTAssertEqual(PanelCommand.from(keyCode: 76, control: false), .activate)
    }
}
