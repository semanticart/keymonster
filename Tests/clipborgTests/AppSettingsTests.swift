import XCTest
@testable import clipborg

@MainActor
final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "clipborgTests.AppSettings"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testSettingShortcutPersists() {
        let settings = AppSettings(defaults: defaults)
        settings.shortcut = Shortcut(keyCode: 9, carbonModifiers: 0x0100 | 0x0200)

        // A fresh instance backed by the same store should reload it.
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.shortcut, settings.shortcut)
    }

    func testClearingShortcutRemovesIt() {
        let settings = AppSettings(defaults: defaults)
        settings.shortcut = Shortcut(keyCode: 9, carbonModifiers: 0x0100)
        settings.shortcut = nil

        XCTAssertNil(defaults.data(forKey: AppSettings.shortcutKey))
        XCTAssertNil(AppSettings(defaults: defaults).shortcut)
    }

    func testStartsEmptyWhenNothingStored() {
        XCTAssertNil(AppSettings(defaults: defaults).shortcut)
    }

    func testAutoPasteDefaultsOnWhenNothingStored() {
        XCTAssertTrue(AppSettings(defaults: defaults).autoPaste)
    }

    func testAutoPastePersists() {
        let settings = AppSettings(defaults: defaults)
        settings.autoPaste = false

        XCTAssertFalse(AppSettings(defaults: defaults).autoPaste)
    }

    func testHasLaunchedStartsFalseThenPersists() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.hasLaunched)
        settings.hasLaunched = true

        XCTAssertTrue(AppSettings(defaults: defaults).hasLaunched)
    }
}
