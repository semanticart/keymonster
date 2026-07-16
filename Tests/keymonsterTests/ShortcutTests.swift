import AppKit
import XCTest
@testable import keymonster

final class ShortcutFormatterTests: XCTestCase {
    private let cmdKey = Int(CarbonModifierMask.command)
    private let shiftKey = Int(CarbonModifierMask.shift)
    private let optionKey = Int(CarbonModifierMask.option)
    private let controlKey = Int(CarbonModifierMask.control)

    func testCmdShiftV() {
        // keyCode 9 == "V"
        let result = ShortcutFormatter.format(keyCode: 9, carbonModifiers: cmdKey | shiftKey)
        XCTAssertEqual(result, "⇧⌘V")
    }

    func testModifierOrderIsControlOptionShiftCommand() {
        // keyCode 49 == "Space"; all modifiers set should render in a fixed order.
        let result = ShortcutFormatter.format(
            keyCode: 49,
            carbonModifiers: cmdKey | shiftKey | optionKey | controlKey
        )
        XCTAssertEqual(result, "⌃⌥⇧⌘Space")
    }

    func testNoModifiers() {
        // keyCode 36 == Return symbol.
        XCTAssertEqual(ShortcutFormatter.format(keyCode: 36, carbonModifiers: 0), "↩")
    }

    func testUnknownKeyCodeFallsBackToQuestionMark() {
        XCTAssertEqual(ShortcutFormatter.format(keyCode: 999, carbonModifiers: cmdKey), "⌘?")
    }
}

final class CarbonModifiersTests: XCTestCase {
    func testMapsEachFlagToCarbonBit() {
        XCTAssertEqual(carbonModifiers(from: .command), CarbonModifierMask.command)
        XCTAssertEqual(carbonModifiers(from: .shift), CarbonModifierMask.shift)
        XCTAssertEqual(carbonModifiers(from: .option), CarbonModifierMask.option)
        XCTAssertEqual(carbonModifiers(from: .control), CarbonModifierMask.control)
    }

    func testCombinesFlags() {
        let mods = carbonModifiers(from: [.command, .shift])
        XCTAssertEqual(mods, CarbonModifierMask.command | CarbonModifierMask.shift)
    }

    func testIgnoresNonModifierFlags() {
        // capsLock should not contribute any Carbon bits.
        XCTAssertEqual(carbonModifiers(from: [.command, .capsLock]), CarbonModifierMask.command)
    }

    func testFormatterRoundTripsRecorderOutput() {
        // Simulate the recorder path: NSEvent flags -> carbon bits -> display string.
        let mods = carbonModifiers(from: [.command, .shift])
        let shortcut = Shortcut(keyCode: 9, carbonModifiers: mods)
        XCTAssertEqual(shortcut.displayString, "⇧⌘V")
    }
}

final class ShortcutCodableTests: XCTestCase {
    func testEncodeDecodeRoundTrip() throws {
        let original = Shortcut(keyCode: 9, carbonModifiers: CarbonModifierMask.command | CarbonModifierMask.shift)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

final class ShortcutConflictsTests: XCTestCase {
    private func shortcut(_ key: UInt32, _ mods: UInt32 = CarbonModifierMask.command) -> Shortcut {
        Shortcut(keyCode: key, carbonModifiers: mods)
    }

    func testNoConflictsWhenAllUnique() {
        let result = ShortcutConflicts.conflicting([shortcut(0), shortcut(1), shortcut(2)])
        XCTAssertTrue(result.isEmpty)
    }

    func testDetectsADuplicate() {
        let dup = shortcut(0)
        let result = ShortcutConflicts.conflicting([dup, shortcut(1), dup])
        XCTAssertEqual(result, [dup])
    }

    func testSameKeyDifferentModifiersDoNotConflict() {
        let result = ShortcutConflicts.conflicting([
            shortcut(0, CarbonModifierMask.command),
            shortcut(0, CarbonModifierMask.shift)
        ])
        XCTAssertTrue(result.isEmpty)
    }

    func testReportsEachConflictingComboOnce() {
        let first = shortcut(0)
        let second = shortcut(1)
        let result = ShortcutConflicts.conflicting([first, first, first, second, second])
        XCTAssertEqual(result, [first, second])
    }

    func testEmptyInputHasNoConflicts() {
        XCTAssertTrue(ShortcutConflicts.conflicting([]).isEmpty)
    }
}
