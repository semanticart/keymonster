import AppKit
import XCTest
@testable import clipborg

final class ShortcutFormatterTests: XCTestCase {
    // Carbon modifier bit constants, mirrored from AppSettings.
    private let cmdKey = 0x0100
    private let shiftKey = 0x0200
    private let optionKey = 0x0800
    private let controlKey = 0x1000

    func testCmdShiftV() {
        // keyCode 9 == "V"
        let s = ShortcutFormatter.format(keyCode: 9, carbonModifiers: cmdKey | shiftKey)
        XCTAssertEqual(s, "⇧⌘V")
    }

    func testModifierOrderIsControlOptionShiftCommand() {
        // keyCode 49 == "Space"; all modifiers set should render in a fixed order.
        let s = ShortcutFormatter.format(
            keyCode: 49,
            carbonModifiers: cmdKey | shiftKey | optionKey | controlKey
        )
        XCTAssertEqual(s, "⌃⌥⇧⌘Space")
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
        XCTAssertEqual(carbonModifiers(from: .command), 0x0100)
        XCTAssertEqual(carbonModifiers(from: .shift), 0x0200)
        XCTAssertEqual(carbonModifiers(from: .option), 0x0800)
        XCTAssertEqual(carbonModifiers(from: .control), 0x1000)
    }

    func testCombinesFlags() {
        let mods = carbonModifiers(from: [.command, .shift])
        XCTAssertEqual(mods, 0x0100 | 0x0200)
    }

    func testIgnoresNonModifierFlags() {
        // capsLock should not contribute any Carbon bits.
        XCTAssertEqual(carbonModifiers(from: [.command, .capsLock]), 0x0100)
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
        let original = Shortcut(keyCode: 9, carbonModifiers: 0x0100 | 0x0200)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Shortcut.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
