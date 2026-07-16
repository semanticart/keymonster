import XCTest
@testable import keymonster

final class TextMatchesTests: XCTestCase {
    func testFindsEveryOccurrence() {
        XCTAssertEqual(TextMatches.offsets(of: "a", in: "banana"), [1, 3, 5])
    }

    func testMatchingIsCaseInsensitive() {
        // Pressing "a" should find both cases; the offsets are the A positions.
        XCTAssertEqual(TextMatches.offsets(of: "a", in: "Abracadabra"), [0, 3, 5, 7, 10])
        XCTAssertEqual(TextMatches.offsets(of: "S", in: "MiSSISSippi"), [2, 3, 5, 6])
    }

    func testMatchesDigitsPunctuationAndSpaces() {
        XCTAssertEqual(TextMatches.offsets(of: "2", in: "a2b2c2"), [1, 3, 5])
        XCTAssertEqual(TextMatches.offsets(of: ".", in: "a.b.c"), [1, 3])
        XCTAssertEqual(TextMatches.offsets(of: " ", in: "a b c"), [1, 3])
    }

    func testNoMatchIsEmpty() {
        XCTAssertTrue(TextMatches.offsets(of: "z", in: "banana").isEmpty)
        XCTAssertTrue(TextMatches.offsets(of: "a", in: "").isEmpty)
    }

    func testOffsetsAreUTF16UnitsPastAstralCharacters() {
        // "😀" is two UTF-16 units, so the "b" that follows sits at offset 3, not
        // 2 — AX text ranges count UTF-16 units, and these offsets feed straight
        // into kAXBoundsForRange / kAXSelectedTextRange.
        XCTAssertEqual(TextMatches.offsets(of: "b", in: "a😀b"), [3])
    }
}

final class TextJumpSettingsTests: XCTestCase {
    @MainActor
    func testTextJumpShortcutPersistsAcrossInstances() {
        let suite = "textjump-settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.textJumpShortcut = Shortcut(keyCode: 40, carbonModifiers: 0x0100 | 0x1000)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(
            reloaded.textJumpShortcut,
            Shortcut(keyCode: 40, carbonModifiers: 0x0100 | 0x1000)
        )

        reloaded.textJumpShortcut = nil
        XCTAssertNil(AppSettings(defaults: defaults).textJumpShortcut)
    }
}
