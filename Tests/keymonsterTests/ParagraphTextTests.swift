import CoreGraphics
import XCTest
@testable import keymonster

/// A tree shaped like Chromium's contenteditable: an `AXTextArea` whose
/// paragraphs are child groups of leaf `AXStaticText`s, an empty paragraph
/// being an empty group. Bounds are irrelevant here.
private struct ParagraphTree: AXTextTree {
    struct Node {
        var role: String
        var value: String?
        var description: String?
        var children: [Node] = []
    }

    func children(of element: Node) -> [Node] { element.children }
    func stringValue(of element: Node) -> String? { element.value }
    func role(of element: Node) -> String? { element.role }
    func description(of element: Node) -> String? { element.description }
    func bounds(of element: Node, at offset: Int) -> CGRect? { nil }

    static func paragraph(_ leaves: String...) -> Node {
        paragraph(leaves.map { Node(role: "AXStaticText", value: $0) })
    }

    static func paragraph(_ leaves: [Node]) -> Node {
        Node(role: "AXGroup", value: "", children: leaves)
    }

    static func text(_ value: String) -> Node { Node(role: "AXStaticText", value: value) }

    /// An emoji as Slack's composer exposes it (captured 2026-09-07): an
    /// `AXImage` with an empty value, a 1×1 data-URL `AXURL`, DOM class
    /// `emoji`, and Slack's short name plus " emoji" as the description —
    /// "tada emoji", not Unicode's "party popper". Nothing else identifies it.
    static func emoji(_ slackName: String) -> Node {
        Node(role: "AXImage", value: "", description: "\(slackName) emoji")
    }
}

final class ParagraphTextTests: XCTestCase {
    /// Slack's composer as captured 2026-09-04: three paragraphs, the middle
    /// one empty, and a value that reads as if the blank line weren't there.
    private let slack = ParagraphTree.Node(
        role: "AXTextArea", value: "first paragraph\nsecond paragraph",
        children: [
            ParagraphTree.paragraph("first paragraph"),
            ParagraphTree.paragraph(),
            ParagraphTree.paragraph("second paragraph")
        ]
    )

    func testEmptyParagraphsReadAsBlankLines() {
        XCTAssertEqual(
            ParagraphText.paragraphs(of: slack, in: ParagraphTree()),
            ["first paragraph", "", "second paragraph"]
        )
    }

    func testRestoresTheBlankLineChromiumDrops() {
        let paragraphs = ParagraphText.paragraphs(of: slack, in: ParagraphTree())
        XCTAssertEqual(
            ParagraphText.restoringBlankLines(in: slack.value!, paragraphs: paragraphs),
            "first paragraph\n\nsecond paragraph"
        )
    }

    func testInlineLeavesConcatenateWithinAParagraph() {
        let node = ParagraphTree.Node(
            role: "AXTextArea", value: "bold and plain\nnext",
            children: [
                ParagraphTree.paragraph("bold", " and ", "plain"),
                ParagraphTree.paragraph(),
                ParagraphTree.paragraph("next")
            ]
        )
        let paragraphs = ParagraphText.paragraphs(of: node, in: ParagraphTree())
        XCTAssertEqual(paragraphs, ["bold and plain", "", "next"])
        XCTAssertEqual(
            ParagraphText.restoringBlankLines(in: node.value!, paragraphs: paragraphs),
            "bold and plain\n\nnext"
        )
    }

    func testAgreeingParagraphsLeaveTheValueAlone() {
        let node = ParagraphTree.Node(
            role: "AXTextArea", value: "one\ntwo",
            children: [ParagraphTree.paragraph("one"), ParagraphTree.paragraph("two")]
        )
        let paragraphs = ParagraphText.paragraphs(of: node, in: ParagraphTree())
        XCTAssertEqual(ParagraphText.restoringBlankLines(in: "one\ntwo", paragraphs: paragraphs), "one\ntwo")
    }

    func testNativeAndWebKitShapesAreUntouched() {
        // A native field has no children; WebKit puts the text straight in a leaf.
        let native = ParagraphTree.Node(role: "AXTextField", value: "hello\n\nthere")
        XCTAssertEqual(
            ParagraphText.restoringBlankLines(
                in: native.value!, paragraphs: ParagraphText.paragraphs(of: native, in: ParagraphTree())
            ),
            "hello\n\nthere"
        )
        let webkit = ParagraphTree.Node(
            role: "AXTextArea", value: "hello",
            children: [ParagraphTree.Node(role: "AXStaticText", value: "hello")]
        )
        XCTAssertEqual(
            ParagraphText.restoringBlankLines(
                in: webkit.value!, paragraphs: ParagraphText.paragraphs(of: webkit, in: ParagraphTree())
            ),
            "hello"
        )
    }

    func testDisagreeingParagraphsFallBackToTheValue() {
        // Leaves that don't carry everything the value does (an emoji image,
        // say) mean the reconstruction can't be trusted.
        XCTAssertEqual(
            ParagraphText.restoringBlankLines(in: "hi 🙂\nbye", paragraphs: ["hi ", "", "bye"]),
            "hi 🙂\nbye"
        )
        // Fewer newlines than the value is not the story this fixes.
        XCTAssertEqual(ParagraphText.restoringBlankLines(in: "a\n", paragraphs: ["a"]), "a\n")
        XCTAssertEqual(ParagraphText.restoringBlankLines(in: "a\nb", paragraphs: nil), "a\nb")
        XCTAssertEqual(ParagraphText.restoringBlankLines(in: "a\nb", paragraphs: []), "a\nb")
    }

    func testTheAXWriteThatDoublesNewlinesIsVisible() {
        // What Slack looks like after an AX value write of "x\ny": the
        // paragraph read exposes the extra blank line the raw value hides.
        let node = ParagraphTree.Node(
            role: "AXTextArea", value: "x\ny",
            children: [ParagraphTree.paragraph("x"), ParagraphTree.paragraph(), ParagraphTree.paragraph("y")]
        )
        let read = ParagraphText.restoringBlankLines(
            in: node.value!, paragraphs: ParagraphText.paragraphs(of: node, in: ParagraphTree())
        )
        XCTAssertNotEqual(read, "x\ny")
        XCTAssertEqual(read, "x\n\ny")
    }

    /// The read `AXFocusedText.wholeValue` performs, against a fixture.
    private func read(_ node: ParagraphTree.Node) -> String {
        ParagraphText.wholeText(value: node.value!, of: node, in: ParagraphTree())
    }

    /// The reported case, without an emoji: a blank line between two lines.
    /// Slack's value drops the blank line; the paragraphs put it back.
    func testBlankLineBetweenTwoLinesSurvivesTheRead() {
        let node = ParagraphTree.Node(
            role: "AXTextArea", value: "this is line one\nthis is line three",
            children: [
                ParagraphTree.paragraph("this is line one"),
                ParagraphTree.paragraph(),
                ParagraphTree.paragraph("this is line three")
            ]
        )
        XCTAssertEqual(read(node), "this is line one\n\nthis is line three")
    }

    /// Slack's composer holding "this is line one 🙂⏎⏎this is line three 🎉 done",
    /// captured 2026-09-07. The raw value drops each emoji and puts newlines
    /// where it was: one at a line's end (which then passes for the blank
    /// line), two in the middle of a line. The paragraphs still say where
    /// each emoji is, and its description says which one. The read should
    /// give the text the user sees.
    func testEmojisSurviveTheReadAndTheBlankLineIsStillOne() {
        let node = ParagraphTree.Node(
            role: "AXTextArea", value: "this is line one \n\nthis is line three \n\n done",
            children: [
                ParagraphTree.paragraph([
                    ParagraphTree.text("this is line one "), ParagraphTree.emoji("slightly smiling face")
                ]),
                ParagraphTree.paragraph(),
                ParagraphTree.paragraph([
                    ParagraphTree.text("this is line three "), ParagraphTree.emoji("tada"), ParagraphTree.text(" done")
                ])
            ]
        )
        XCTAssertEqual(read(node), "this is line one 🙂\n\nthis is line three 🎉 done")
    }

    /// Same capture, the smallest shape: an emoji between two words on one
    /// line. The value reads "a \n\n b" — a phantom blank line and no emoji.
    func testEmojiMidLineIsKeptAndAddsNoBlankLine() {
        let node = ParagraphTree.Node(
            role: "AXTextArea", value: "a \n\n b",
            children: [
                ParagraphTree.paragraph([
                    ParagraphTree.text("a "), ParagraphTree.emoji("slightly smiling face"), ParagraphTree.text(" b")
                ])
            ]
        )
        XCTAssertEqual(read(node), "a 🙂 b")
    }

    /// An emoji at the end of a line before a blank line: the value's newline
    /// for the emoji and the paragraph join coincide, so the blank line looks
    /// preserved while the emoji is gone. Both must come through.
    func testEmojiAtLineEndBeforeABlankLine() {
        let node = ParagraphTree.Node(
            role: "AXTextArea", value: "end \n\nx",
            children: [
                ParagraphTree.paragraph([ParagraphTree.text("end "), ParagraphTree.emoji("slightly smiling face")]),
                ParagraphTree.paragraph(),
                ParagraphTree.paragraph("x")
            ]
        )
        XCTAssertEqual(read(node), "end 🙂\n\nx")
    }

    func testOversizedTreesGiveUp() {
        let huge = ParagraphTree.Node(
            role: "AXTextArea", value: "",
            children: (0..<10).map { _ in ParagraphTree.paragraph("p") }
        )
        XCTAssertNil(ParagraphText.paragraphs(of: huge, in: ParagraphTree(), limit: 5))
        XCTAssertNotNil(ParagraphText.paragraphs(of: huge, in: ParagraphTree(), limit: 20))
    }
}
