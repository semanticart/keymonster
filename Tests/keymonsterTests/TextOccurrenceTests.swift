import CoreGraphics
import XCTest
@testable import keymonster

/// An accessibility tree recorded from a real app, so the occurrence search can
/// be tested against the shapes that actually ship. Reading a live tree needs an
/// Accessibility grant that CI can't hold, so the numbers in `RecordedTrees`
/// below were captured from real apps by hand and pasted in.
private struct RecordedTree: AXTextTree {
    /// What an element answers when asked for a character's bounds. Real fields
    /// do all three, which is why the search can't just trust a reply.
    enum Geometry {
        /// Real per-character rects, laid out left to right from `origin` — what
        /// a native AppKit field and a web leaf `AXStaticText` both answer.
        case glyphs(origin: CGPoint, size: CGSize)
        /// The same degenerate rect at every offset — what Chromium's editable
        /// containers answer.
        case junk(CGRect)
        /// Nothing at all — what an element that doesn't implement
        /// `AXBoundsForRange` answers.
        case nothing
    }

    struct Node {
        let role: String
        var value: String?
        var geometry: Geometry = .nothing
        var children: [Node] = []
    }

    func children(of element: Node) -> [Node] { element.children }
    func stringValue(of element: Node) -> String? { element.value }
    func role(of element: Node) -> String? { element.role }

    func bounds(of element: Node, at offset: Int) -> CGRect? {
        switch element.geometry {
        case .glyphs(let origin, let size):
            return CGRect(
                x: origin.x + CGFloat(offset) * size.width, y: origin.y,
                width: size.width, height: size.height
            )
        case .junk(let rect):
            return rect
        case .nothing:
            return nil
        }
    }
}

/// The trees, as captured. Each comment records where the numbers came from so
/// a future reader can tell a real quirk from an invented one.
private enum RecordedTrees {
    /// Chrome's omnibox, captured 2026-07-28 (Chrome on macOS 26.5). Its
    /// parameterized attribute list has no `AXBoundsForRange` at all, the call
    /// answers a degenerate rect anyway, and the element has zero children — so
    /// there is neither geometry nor a leaf to fall back to.
    static let chromeOmnibox = RecordedTree.Node(
        role: "AXTextField",
        value: "https://claude.ai/chat/5d4bbed8-6bab-4a37-a0b0-3b1433e527b2",
        geometry: .junk(CGRect(x: 0, y: 1117, width: 0, height: 0))
    )

    /// Slack's message input, captured the same day. The editable container
    /// answers the same junk rect as Chrome, but its one leaf `AXStaticText`
    /// carries intact 8x18 glyph boxes starting at (865, 915).
    static let slackInput = RecordedTree.Node(
        role: "AXTextArea",
        value: "yo what is up hello my baby",
        geometry: .junk(CGRect(x: 0, y: 1117, width: 0, height: 0)),
        children: [
            RecordedTree.Node(
                role: "AXStaticText",
                value: "yo what is up hello my baby",
                geometry: .glyphs(origin: CGPoint(x: 865, y: 915), size: CGSize(width: 8, height: 18))
            )
        ]
    )

    /// A native AppKit field: bounds come straight off the field itself and it
    /// has no children to walk.
    static let nativeField = RecordedTree.Node(
        role: "AXTextField",
        value: "hello world hello",
        geometry: .glyphs(origin: CGPoint(x: 100, y: 200), size: CGSize(width: 7, height: 16))
    )

    /// A web field whose text is split across several leaves, as WebKit reports
    /// a contenteditable with inline markup in it.
    static let multiLeafWeb = RecordedTree.Node(
        role: "AXTextArea",
        value: "onetwo",
        geometry: .junk(CGRect(x: 0, y: 1117, width: 0, height: 0)),
        children: [
            RecordedTree.Node(
                role: "AXStaticText", value: "one",
                geometry: .glyphs(origin: CGPoint(x: 10, y: 50), size: CGSize(width: 6, height: 14))
            ),
            RecordedTree.Node(
                role: "AXStaticText", value: "two",
                geometry: .glyphs(origin: CGPoint(x: 40, y: 50), size: CGSize(width: 6, height: 14))
            )
        ]
    )
}

final class TextOccurrenceTests: XCTestCase {
    private let window = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let budget = TextSearchBudget(
        maxOccurrences: 100, maxLeafNodes: 100, hasTimeLeft: { true }
    )

    private func find(
        _ character: Character, in node: RecordedTree.Node,
        window: CGRect? = nil, budget: TextSearchBudget? = nil
    ) -> [TextOccurrence] {
        TextSearch(
            tree: RecordedTree(), window: window ?? self.window, budget: budget ?? self.budget
        ).find(character, in: node.value ?? "", element: node)
    }

    // MARK: - Native fields

    func testNativeFieldReadsBoundsOffTheFieldItself() {
        let hits = find("h", in: RecordedTrees.nativeField)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].rect, CGRect(x: 100, y: 200, width: 7, height: 16))
        XCTAssertEqual(hits[0].caret, .offset(0))
        XCTAssertEqual(hits[1].rect, CGRect(x: 184, y: 200, width: 7, height: 16))
        XCTAssertEqual(hits[1].caret, .offset(12))
    }

    func testNativeMatchingIgnoresCase() {
        XCTAssertEqual(find("H", in: RecordedTrees.nativeField).count, 2)
    }

    func testOccurrencesOutsideTheWindowAreDropped() {
        // A window that ends before the second "h" at x=184.
        let narrow = CGRect(x: 0, y: 0, width: 150, height: 1117)
        let hits = find("h", in: RecordedTrees.nativeField, window: narrow)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].caret, .offset(0))
    }

    // MARK: - Web fields

    func testSlackFallsThroughJunkBoundsToItsLeaf() {
        let hits = find("h", in: RecordedTrees.slackInput)
        XCTAssertEqual(hits.count, 2, "the container's junk rect must not be mistaken for geometry")
        // Glyph 4 of "yo what is up hello my baby" starts at 865 + 4*8.
        XCTAssertEqual(hits[0].rect, CGRect(x: 897, y: 915, width: 8, height: 18))
        XCTAssertEqual(hits[1].rect, CGRect(x: 977, y: 915, width: 8, height: 18))
    }

    func testWebCaretsClickTheLeftEdgeOfTheGlyph() {
        let hits = find("h", in: RecordedTrees.slackInput)
        // A quarter into an 8pt glyph, vertically centred in an 18pt line.
        XCTAssertEqual(hits[0].caret, .click(CGPoint(x: 899, y: 924)))
        XCTAssertEqual(hits[1].caret, .click(CGPoint(x: 979, y: 924)))
    }

    func testLeavesAreWalkedInReadingOrder() {
        let hits = find("o", in: RecordedTrees.multiLeafWeb)
        XCTAssertEqual(hits.count, 2)
        // "one" leaf at x=10, offset 0; then "two" leaf at x=40, offset 2.
        XCTAssertEqual(hits[0].rect.minX, 10)
        XCTAssertEqual(hits[1].rect.minX, 52)
    }

    // MARK: - Chrome's omnibox

    func testChromeOmniboxFindsNothing() {
        // Documents a known gap rather than a desired outcome: the omnibox
        // exposes no per-character geometry and no leaves, so there is nowhere
        // to put a badge and text jump can only beep. If this ever starts
        // returning hits, the omnibox got geometry and this should say so.
        XCTAssertTrue(find("c", in: RecordedTrees.chromeOmnibox).isEmpty)
    }

    func testChromeOmniboxCaretIsStillAddressableByOffset() {
        // The reason the gap is worth closing: the text is readable and the
        // offsets are real, it's only the geometry that's missing.
        XCTAssertEqual(
            TextMatches.offsets(of: "?", in: "https://example.com/a?b=c"), [21]
        )
    }

    // MARK: - Budget

    func testOccurrenceCapStopsTheSearch() {
        let capped = TextSearchBudget(maxOccurrences: 1, maxLeafNodes: 100, hasTimeLeft: { true })
        XCTAssertEqual(find("h", in: RecordedTrees.nativeField, budget: capped).count, 1)
    }

    func testExhaustedTimeBudgetStopsTheSearch() {
        let expired = TextSearchBudget(maxOccurrences: 100, maxLeafNodes: 100, hasTimeLeft: { false })
        XCTAssertTrue(find("h", in: RecordedTrees.nativeField, budget: expired).isEmpty)
    }
}
