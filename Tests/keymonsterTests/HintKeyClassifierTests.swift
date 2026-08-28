import AppKit
import XCTest

@testable import keymonster

/// The keystroke rules shared by the event-tap and focus-capture backends.
/// Events are built with `NSEvent.keyEvent` — no window server involved, so
/// these run headless.
final class HintKeyClassifierTests: XCTestCase {
    private func keyEvent(
        _ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
    }

    func testLetterIsReported() {
        let classifier = HintKeyClassifier()
        XCTAssertEqual(
            classifier.classify(keyEvent("a", keyCode: 0)), .letter("a", shifted: false)
        )
    }

    func testShiftedLetterIsLowercasedAndFlagged() {
        let classifier = HintKeyClassifier()
        XCTAssertEqual(
            classifier.classify(keyEvent("a", keyCode: 0, modifiers: .shift)),
            .letter("a", shifted: true)
        )
    }

    func testEscapeAndBackspace() {
        let classifier = HintKeyClassifier()
        XCTAssertEqual(classifier.classify(keyEvent("\u{1b}", keyCode: 53)), .escape)
        XCTAssertEqual(classifier.classify(keyEvent("\u{7f}", keyCode: 51)), .backspace)
    }

    func testChordedKeyIsNotInput() {
        let classifier = HintKeyClassifier()
        XCTAssertNil(classifier.classify(keyEvent("c", keyCode: 8, modifiers: .command)))
    }

    func testEnterOnlyCountsWhenAccepted() {
        var classifier = HintKeyClassifier()
        XCTAssertNil(classifier.classify(keyEvent("\r", keyCode: 36)))
        classifier.acceptsEnter = true
        XCTAssertEqual(classifier.classify(keyEvent("\r", keyCode: 36)), .enter(shifted: false))
    }

    func testExtraCharactersCountAsLetters() {
        var classifier = HintKeyClassifier()
        XCTAssertNil(classifier.classify(keyEvent(";", keyCode: 41)))
        classifier.extraCharacters = [";"]
        XCTAssertEqual(
            classifier.classify(keyEvent(";", keyCode: 41)), .letter(";", shifted: false)
        )
    }

    func testRawModeReportsAnyPrintableVerbatim() {
        var classifier = HintKeyClassifier()
        classifier.reportsRawCharacters = true
        XCTAssertEqual(
            classifier.classify(keyEvent("7", keyCode: 26)), .letter("7", shifted: false)
        )
        XCTAssertEqual(
            classifier.classify(keyEvent("A", keyCode: 0, modifiers: .shift)),
            .letter("A", shifted: true)
        )
        // Control keys (Tab) still aren't input, even raw.
        XCTAssertNil(classifier.classify(keyEvent("\t", keyCode: 48)))
    }
}
