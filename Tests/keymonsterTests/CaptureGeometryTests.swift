import XCTest
@testable import keymonster

final class CaptureGeometryTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    private let above = CGRect(x: 100, y: -1080, width: 1920, height: 1080)

    func testRectOnOneDisplayIsOffsetByThatDisplaysOrigin() {
        let plan = CaptureGeometry.plan(
            bounds: CGRect(x: 1500, y: 100, width: 200, height: 50), displays: [main, right]
        )
        XCTAssertEqual(plan, CapturePlan(
            displayIndex: 1, source: CGRect(x: 60, y: 100, width: 200, height: 50)
        ))
    }

    func testRectOnPrimaryDisplayKeepsItsCoordinates() {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 160)
        XCTAssertEqual(
            CaptureGeometry.plan(bounds: bounds, displays: [main, right]),
            CapturePlan(displayIndex: 0, source: bounds)
        )
    }

    func testStraddlingRectKeepsTheDisplayHoldingMostOfIt() {
        // 100pt on the main display, 300pt on the right one.
        let plan = CaptureGeometry.plan(
            bounds: CGRect(x: 1340, y: 0, width: 400, height: 100), displays: [main, right]
        )
        XCTAssertEqual(plan?.displayIndex, 1)
        XCTAssertEqual(plan?.source, CGRect(x: 0, y: 0, width: 300, height: 100))
    }

    func testDisplayAboveThePrimaryHasNegativeGlobalY() {
        let plan = CaptureGeometry.plan(
            bounds: CGRect(x: 200, y: -500, width: 100, height: 100), displays: [main, above]
        )
        XCTAssertEqual(plan, CapturePlan(
            displayIndex: 1, source: CGRect(x: 100, y: 580, width: 100, height: 100)
        ))
    }

    func testRectPartlyOffEveryDisplayIsClipped() {
        let plan = CaptureGeometry.plan(
            bounds: CGRect(x: -50, y: 850, width: 200, height: 200), displays: [main]
        )
        XCTAssertEqual(plan?.source, CGRect(x: 0, y: 850, width: 150, height: 50))
    }

    func testRectOnNoDisplayHasNoPlan() {
        XCTAssertNil(CaptureGeometry.plan(
            bounds: CGRect(x: 5000, y: 5000, width: 10, height: 10), displays: [main, right]
        ))
        XCTAssertNil(CaptureGeometry.plan(bounds: .zero, displays: [main]))
        XCTAssertNil(CaptureGeometry.plan(bounds: main, displays: []))
    }

    func testRectTouchingOnlyAnEdgeHasNoPlan() {
        XCTAssertNil(CaptureGeometry.plan(
            bounds: CGRect(x: 1440, y: 0, width: 50, height: 50), displays: [main]
        ))
    }
}
