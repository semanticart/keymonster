import XCTest
@testable import keymonster

final class AppFocusTests: XCTestCase {
    func testReturnsNilForNoCandidates() {
        XCTAssertNil(AppFocus.nextTarget(candidates: [], frontmost: "com.apple.Safari"))
    }

    func testFocusesFirstWhenNoneAreFrontmost() {
        let result = AppFocus.nextTarget(
            candidates: ["com.tinyspeck.slackmacgap", "com.google.Chrome"],
            frontmost: "com.apple.Terminal"
        )
        XCTAssertEqual(result, "com.tinyspeck.slackmacgap")
    }

    func testFocusesFirstWhenNothingIsFrontmost() {
        let result = AppFocus.nextTarget(candidates: ["a", "b"], frontmost: nil)
        XCTAssertEqual(result, "a")
    }

    func testCyclesToNextWhenACandidateIsFrontmost() {
        let result = AppFocus.nextTarget(
            candidates: ["com.tinyspeck.slackmacgap", "com.google.Chrome"],
            frontmost: "com.tinyspeck.slackmacgap"
        )
        XCTAssertEqual(result, "com.google.Chrome")
    }

    func testCyclesWrapAroundFromLastToFirst() {
        let result = AppFocus.nextTarget(
            candidates: ["a", "b", "c"],
            frontmost: "c"
        )
        XCTAssertEqual(result, "a")
    }

    func testSingleCandidateStaysOnItself() {
        let result = AppFocus.nextTarget(candidates: ["only"], frontmost: "only")
        XCTAssertEqual(result, "only")
    }
}
