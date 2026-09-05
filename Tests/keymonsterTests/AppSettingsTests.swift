import XCTest
@testable import keymonster

@MainActor
final class AppSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "keymonsterTests.AppSettings"

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

    func testCheckForUpdatesDefaultsOnAndPersistsOptOut() {
        XCTAssertTrue(AppSettings(defaults: defaults).checkForUpdates)

        let settings = AppSettings(defaults: defaults)
        settings.checkForUpdates = false
        XCTAssertFalse(AppSettings(defaults: defaults).checkForUpdates)
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

    func testAppShortcutsStartEmptyWhenNothingStored() {
        XCTAssertTrue(AppSettings(defaults: defaults).appShortcuts.isEmpty)
    }

    func testAppShortcutsPersist() {
        let settings = AppSettings(defaults: defaults)
        let entry = AppShortcut(
            shortcut: Shortcut(keyCode: 0, carbonModifiers: 0x0100),
            apps: [AppRef(bundleID: "com.apple.Safari", name: "Safari")]
        )
        settings.appShortcuts = [entry]

        XCTAssertEqual(AppSettings(defaults: defaults).appShortcuts, [entry])
    }

    func testClearingAppShortcutsRemovesThem() {
        let settings = AppSettings(defaults: defaults)
        settings.appShortcuts = [AppShortcut()]
        settings.appShortcuts = []

        XCTAssertNil(defaults.data(forKey: AppSettings.appShortcutsKey))
        XCTAssertTrue(AppSettings(defaults: defaults).appShortcuts.isEmpty)
    }

    func testScriptShortcutsStartEmptyWhenNothingStored() {
        XCTAssertTrue(AppSettings(defaults: defaults).scriptShortcuts.isEmpty)
    }

    func testScriptShortcutsPersist() {
        let settings = AppSettings(defaults: defaults)
        let entry = ScriptShortcut(
            shortcut: Shortcut(keyCode: 11, carbonModifiers: 0x0100),
            path: "/Users/me/bin/toggle-dark-mode.scpt"
        )
        settings.scriptShortcuts = [entry]

        XCTAssertEqual(AppSettings(defaults: defaults).scriptShortcuts, [entry])
    }

    func testClearingScriptShortcutsRemovesThem() {
        let settings = AppSettings(defaults: defaults)
        settings.scriptShortcuts = [ScriptShortcut()]
        settings.scriptShortcuts = []

        XCTAssertNil(defaults.data(forKey: AppSettings.scriptShortcutsKey))
        XCTAssertTrue(AppSettings(defaults: defaults).scriptShortcuts.isEmpty)
    }

    func testHasLaunchedStartsFalseThenPersists() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.hasLaunched)
        settings.hasLaunched = true

        XCTAssertTrue(AppSettings(defaults: defaults).hasLaunched)
    }

    func testSuspendHotkeysDefaultsFalseAndIsNotPersisted() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertFalse(settings.suspendHotkeys)
        settings.suspendHotkeys = true

        // Transient recording state, not user data: a fresh instance never sees it.
        XCTAssertFalse(AppSettings(defaults: defaults).suspendHotkeys)
    }
}

@MainActor
final class EditorSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "keymonsterTests.EditorSettings"

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

    func testEditorSettingsStartEmpty() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertNil(settings.editInEditorShortcut)
        XCTAssertEqual(settings.editorCommand, "")
        XCTAssertNil(settings.editorTerminal)
    }

    func testEditorSettingsPersist() {
        let settings = AppSettings(defaults: defaults)
        settings.editInEditorShortcut = Shortcut(keyCode: 14, carbonModifiers: 0x1000 | 0x0200)
        settings.editorCommand = "code --wait"
        settings.editorTerminal = AppRef(bundleID: "net.kovidgoyal.kitty", name: "kitty")

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.editInEditorShortcut, settings.editInEditorShortcut)
        XCTAssertEqual(reloaded.editorCommand, "code --wait")
        XCTAssertEqual(reloaded.editorTerminal, AppRef(bundleID: "net.kovidgoyal.kitty", name: "kitty"))
    }

    func testClearingEditorSettingsRemovesThem() {
        let settings = AppSettings(defaults: defaults)
        settings.editorCommand = "nvim"
        settings.editorTerminal = AppRef(bundleID: "com.apple.Terminal", name: "Terminal")
        settings.editorCommand = "   "
        settings.editorTerminal = nil

        XCTAssertNil(defaults.object(forKey: AppSettings.editorCommandKey))
        XCTAssertNil(defaults.data(forKey: AppSettings.editorTerminalKey))
        XCTAssertEqual(AppSettings(defaults: defaults).editorCommand, "")
    }
}
