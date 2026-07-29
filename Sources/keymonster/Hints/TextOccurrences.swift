import CoreGraphics
import Foundation

/// How to drop the caret before a matched character.
enum TextCaret: Equatable {
    /// Native fields: a zero-length `AXSelectedTextRange` at this UTF-16 offset.
    case offset(Int)
    /// Web fields: a synthesized click at this point (the character's left edge).
    case click(CGPoint)
}

/// One on-screen occurrence of the target character.
struct TextOccurrence: Equatable {
    /// The character's bounding box in AX (global, top-left origin)
    /// coordinates, clipped to the window.
    let rect: CGRect
    /// Where to put the caret to land just before this character.
    let caret: TextCaret
}

/// The slice of the accessibility API the occurrence search reads.
///
/// Behind a protocol so the search itself is pure: `AXFocusedText` supplies the
/// live tree, and the tests supply trees recorded from real apps — Chrome's
/// omnibox, Slack's editable div, a native AppKit field. That recording is the
/// only practical way to cover them: reading a real tree needs an Accessibility
/// grant, and a grant can't be held by CI (an untrusted process can't even read
/// its own tree — the API answers `kAXErrorCannotComplete`).
protocol AXTextTree {
    associatedtype Element

    func children(of element: Element) -> [Element]
    func stringValue(of element: Element) -> String?
    func role(of element: Element) -> String?
    /// The screen rect of the character at `offset`, in AX (global, top-left
    /// origin) coordinates. Nil when the element answers nothing; a degenerate
    /// rect when it answers junk — real fields do both, so callers must reject
    /// empty rects rather than trust a successful reply.
    func bounds(of element: Element, at offset: Int) -> CGRect?
}

/// Bounds so an enormous field (a whole document) can't hang the app while we
/// ask for one bounding box per character.
struct TextSearchBudget {
    let maxOccurrences: Int
    let maxLeafNodes: Int
    /// Answers false once the search has run long enough. A closure rather than
    /// a duration so the rules can be tested without a clock.
    let hasTimeLeft: () -> Bool

    init(maxOccurrences: Int, maxLeafNodes: Int, hasTimeLeft: @escaping () -> Bool) {
        self.maxOccurrences = maxOccurrences
        self.maxLeafNodes = maxLeafNodes
        self.hasTimeLeft = hasTimeLeft
    }

    /// The live app's bounds, starting the clock now.
    static func live(
        maxOccurrences: Int = HintLabels.maxCount,
        maxLeafNodes: Int = 4000,
        seconds: TimeInterval = 0.5
    ) -> TextSearchBudget {
        let start = Date()
        return TextSearchBudget(maxOccurrences: maxOccurrences, maxLeafNodes: maxLeafNodes) {
            Date().timeIntervalSince(start) <= seconds
        }
    }
}

/// Finds every visible occurrence of a character inside a focused text field, by
/// whichever of the two accessibility shapes that field turns out to have.
///
/// Native (AppKit) fields answer `AXBoundsForRange` on the field itself and take
/// an `AXSelectedTextRange` to move the caret. Web fields (Chromium/Electron
/// like Slack) don't: `AXBoundsForRange` on the editable container returns junk.
/// Their per-character geometry lives on the nested leaf `AXStaticText` nodes
/// instead, and the caret is placed with a precise click, since mapping a
/// character offset back onto the container is unreliable there. WebKit sits in
/// between — it answers real bounds on the container, so it takes the native
/// path despite being web content.
struct TextSearch<Tree: AXTextTree> {
    let tree: Tree
    /// Occurrences are clipped to this rect and dropped when they fall outside.
    let window: CGRect
    let budget: TextSearchBudget

    /// Tries the native path (bounds on the field itself) first and falls back
    /// to the leaf-node path for web content.
    func find(_ character: Character, in value: String, element: Tree.Element) -> [TextOccurrence] {
        let native = native(character, in: value, element: element)
        if !native.isEmpty { return native }
        return leaf(character, element: element)
    }

    // MARK: - Native (AppKit) path

    private func native(
        _ character: Character, in value: String, element: Tree.Element
    ) -> [TextOccurrence] {
        var result: [TextOccurrence] = []
        for offset in TextMatches.offsets(of: character, in: value) {
            if result.count >= budget.maxOccurrences { break }
            if !budget.hasTimeLeft() { break }
            guard let rect = tree.bounds(of: element, at: offset),
                  !rect.isEmpty, rect.intersects(window) else { continue }
            result.append(TextOccurrence(rect: rect.intersection(window), caret: .offset(offset)))
        }
        return result
    }

    // MARK: - Web (leaf-node) path

    /// Chromium/Electron editable fields return garbage from `AXBoundsForRange`,
    /// but the character geometry is intact on their nested leaf `AXStaticText`
    /// nodes. Walk those leaves, read per-character bounds from each, and place
    /// the caret with a click since the container's offset space isn't reliable.
    private func leaf(_ character: Character, element: Tree.Element) -> [TextOccurrence] {
        var result: [TextOccurrence] = []
        for leaf in textLeaves(under: element) {
            if result.count >= budget.maxOccurrences { break }
            if !budget.hasTimeLeft() { break }
            guard let text = tree.stringValue(of: leaf) else { continue }
            for offset in TextMatches.offsets(of: character, in: text) {
                if result.count >= budget.maxOccurrences { break }
                guard let rect = tree.bounds(of: leaf, at: offset),
                      !rect.isEmpty, rect.intersects(window) else { continue }
                // Click the left edge of the glyph so the caret lands before it.
                let point = CGPoint(x: rect.minX + max(1, rect.width * 0.25), y: rect.midY)
                result.append(TextOccurrence(rect: rect.intersection(window), caret: .click(point)))
            }
        }
        return result
    }

    /// Depth-first leaf text nodes under `element`, in reading order: elements
    /// with no children that carry a non-empty string value (or are AXStaticText).
    private func textLeaves(under element: Tree.Element) -> [Tree.Element] {
        var result: [Tree.Element] = []
        var stack = tree.children(of: element).reversed().map { $0 }
        var visited = 0
        while let node = stack.popLast(), result.count < budget.maxOccurrences,
              visited < budget.maxLeafNodes {
            visited += 1
            let children = tree.children(of: node)
            if children.isEmpty {
                if tree.stringValue(of: node)?.isEmpty == false || tree.role(of: node) == "AXStaticText" {
                    result.append(node)
                }
            } else {
                stack.append(contentsOf: children.reversed())
            }
        }
        return result
    }
}
