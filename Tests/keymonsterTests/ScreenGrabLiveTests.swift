import AppKit
import XCTest
@testable import keymonster

/// Real ScreenCaptureKit captures; skipped unless the test process has Screen
/// Recording permission (CI and fresh machines don't).
final class ScreenGrabLiveTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(CGPreflightScreenCaptureAccess(), "needs Screen Recording permission")
    }

    func testCaptureIsRegionSizedAtNativeDensity() async throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let bounds = CGRect(x: 100, y: 100, width: 300, height: 160)
        let grabbed = await ScreenGrab.image(of: bounds, excluding: nil)
        let image = try XCTUnwrap(grabbed)
        XCTAssertEqual(image.width, Int(300 * screen.backingScaleFactor))
        XCTAssertEqual(image.height, Int(160 * screen.backingScaleFactor))
    }

    func testRectOnNoDisplayYieldsNil() async {
        let image = await ScreenGrab.image(
            of: CGRect(x: 90_000, y: 90_000, width: 50, height: 50), excluding: nil
        )
        XCTAssertNil(image)
    }

    func testBlockingVariantMatchesAsync() throws {
        let image = try XCTUnwrap(ScreenGrab.imageBlocking(of: CGRect(x: 0, y: 0, width: 80, height: 40)))
        XCTAssertGreaterThan(image.width, 0)
    }
}
