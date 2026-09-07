import XCTest
@testable import keymonster

@MainActor
final class UpdaterTests: XCTestCase {
    func testStaysInactiveWithoutAFeedURL() {
        let updater = Updater(feedURL: nil)
        updater.start(settings: AppSettings(defaults: UserDefaults(suiteName: #function)!))
        XCTAssertFalse(updater.isActive)
        XCTAssertNil(updater.availableVersion)
    }

    func testScheduledUpdateBadgesUntilHandled() {
        let updater = Updater(feedURL: nil)
        updater.noteScheduledUpdate(version: "0.3.0")
        XCTAssertEqual(updater.availableVersion, "0.3.0")

        updater.noteUpdateHandled()
        XCTAssertNil(updater.availableVersion)
    }
}
