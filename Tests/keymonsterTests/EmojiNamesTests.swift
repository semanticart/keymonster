import XCTest
@testable import keymonster

/// Every description here was read off Slack's composer on 2026-09-07 after
/// pasting the emoji in question, so these pin how Slack really names them.
final class EmojiNamesTests: XCTestCase {
    private func text(_ description: String) -> String? {
        EmojiNames.text(forDescription: description)
    }

    func testPlainNames() {
        XCTAssertEqual(text("slightly smiling face emoji"), "\u{1F642}")
        XCTAssertEqual(text("tada emoji"), "\u{1F389}")
        XCTAssertEqual(text("+1 emoji"), "\u{1F44D}")
    }

    /// An alias the user typed (`:thumbsup:`) is described by that alias.
    func testAliasesResolve() {
        XCTAssertEqual(text("thumbsup emoji"), "\u{1F44D}")
        XCTAssertEqual(text("us emoji"), "\u{1F1FA}\u{1F1F8}")
    }

    /// Hyphens and underscores in the short name are both spaces in the
    /// description.
    func testFlattenedNames() {
        XCTAssertEqual(text("e mail emoji"), "\u{1F4E7}")
        XCTAssertEqual(text("non potable water emoji"), "\u{1F6B1}")
        XCTAssertEqual(text("man woman girl emoji"), "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}")
    }

    /// Text-presentation code points keep their variation selector, so the
    /// character pastes back as the emoji Slack showed.
    func testVariationSelectorsAndKeycaps() {
        XCTAssertEqual(text("heart emoji"), "\u{2764}\u{FE0F}")
        XCTAssertEqual(text("copyright emoji"), "\u{A9}\u{FE0F}")
        XCTAssertEqual(text("one emoji"), "1\u{FE0F}\u{20E3}")
        XCTAssertEqual(text("hash emoji"), "#\u{FE0F}\u{20E3}")
        XCTAssertEqual(text("a emoji"), "\u{1F170}\u{FE0F}")
        XCTAssertEqual(text("rainbow flag emoji"), "\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}")
        XCTAssertEqual(text("woman heart man emoji"), "\u{1F469}\u{200D}\u{2764}\u{FE0F}\u{200D}\u{1F468}")
    }

    func testSkinTones() {
        XCTAssertEqual(text("+1 emoji with medium skin tone"), "\u{1F44D}\u{1F3FD}")
        XCTAssertEqual(text("wave emoji with light skin tone"), "\u{1F44B}\u{1F3FB}")
        XCTAssertEqual(text("wave emoji with medium-light skin tone"), "\u{1F44B}\u{1F3FC}")
        XCTAssertEqual(text("wave emoji with medium-dark skin tone"), "\u{1F44B}\u{1F3FE}")
        XCTAssertEqual(text("wave emoji with dark skin tone"), "\u{1F44B}\u{1F3FF}")
    }

    /// A toned emoji drops the variation selector its plain form carries.
    func testSkinToneDisplacesTheVariationSelector() {
        XCTAssertEqual(text("raised hand emoji"), "\u{270B}")
        XCTAssertEqual(text("v emoji"), "\u{270C}\u{FE0F}")
        XCTAssertEqual(text("v emoji with dark skin tone"), "\u{270C}\u{1F3FF}")
    }

    func testTwoSkinTones() {
        XCTAssertEqual(
            text("people holding hands emoji with left light skin tone and right dark skin tone"),
            "\u{1F9D1}\u{1F3FB}\u{200D}\u{1F91D}\u{200D}\u{1F9D1}\u{1F3FF}"
        )
        // A mixed-tone pair the insertion rule can't derive: the table has it.
        XCTAssertEqual(
            text("man and woman holding hands emoji with left light skin tone and right medium-light skin tone"),
            "\u{1F469}\u{1F3FB}\u{200D}\u{1F91D}\u{200D}\u{1F468}\u{1F3FC}"
        )
    }

    /// A workspace's custom emoji has no character; the shortcode is what
    /// Slack turns back into the emoji on paste.
    func testCustomEmojiBecomesItsShortcode() {
        XCTAssertEqual(text("partyparrot emoji"), ":partyparrot:")
        XCTAssertEqual(text("party parrot emoji"), ":party_parrot:")
    }

    func testDescriptionsThatArentSlacksAreNil() {
        XCTAssertNil(text("image"))
        XCTAssertNil(text(""))
        XCTAssertNil(text("emoji"))
        XCTAssertNil(text("wave emoji with purple skin tone"))
        XCTAssertNil(text("wave emoji and more"))
    }

    func testTableParsesEveryLine() {
        let lines = EmojiNamesTable.contents.split(separator: "\n").count
        XCTAssertGreaterThan(lines, 1900)
        // Every line contributes at least one key; aliases add more.
        XCTAssertGreaterThan(EmojiNames.Table.shared.entries.count, lines)
    }
}
