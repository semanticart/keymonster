import AppKit
import ApplicationServices
import CoreGraphics

/// UTF-16 offsets of a character inside a string. AX text ranges
/// (`kAXSelectedTextRange`, `kAXBoundsForRange…`) are measured in UTF-16 code
/// units — the same units `NSString` indexes by — so we walk the `NSString`
/// view rather than Swift's grapheme-cluster `Character`s. Pure so it's testable
/// without a live accessibility tree.
enum TextMatches {
    /// Every UTF-16 offset where `character` occurs in `text`, matched
    /// case-insensitively ("a" finds both "a" and "A").
    static func offsets(of character: Character, in text: String) -> [Int] {
        let target = lowered(character)
        let string = text as NSString
        var result: [Int] = []
        for index in 0..<string.length {
            // Skip halves of surrogate pairs (emoji etc.); a keyboard target
            // character is always a single BMP scalar anyway.
            guard let scalar = Unicode.Scalar(string.character(at: index)) else { continue }
            if lowered(Character(scalar)) == target {
                result.append(index)
            }
        }
        return result
    }

    private static func lowered(_ character: Character) -> String {
        String(character).lowercased()
    }
}

/// Reads and writes the caret of whatever text field is focused system-wide —
/// native or web — so text-jump mode can locate a character and drop the cursor
/// in front of it.
///
/// Native (AppKit) fields answer `AXBoundsForRange` on the field itself and take
/// an `AXSelectedTextRange` to move the caret. Web fields (Chromium/Electron like
/// Slack, and WebKit) don't: `AXBoundsForRange` on the editable container returns
/// junk. Their per-character geometry lives on the nested leaf `AXStaticText`
/// nodes instead, and the caret is placed with a precise click, since mapping a
/// character offset back onto the container is unreliable there.
@MainActor
enum AXFocusedText {
    struct Focus {
        let element: AXUIElement
        /// The field's full text at the moment the mode activated.
        let value: String
    }

    /// How to drop the caret before a matched character.
    enum Caret {
        /// Native fields: a zero-length `AXSelectedTextRange` at this UTF-16 offset.
        case offset(Int)
        /// Web fields: a synthesized click at this point (the character's left edge).
        case click(CGPoint)
    }

    /// One on-screen occurrence of the target character.
    struct Occurrence {
        /// The character's bounding box in AX (global, top-left origin)
        /// coordinates, clipped to the window.
        let rect: CGRect
        /// Where to put the caret to land just before this character.
        let caret: Caret
    }

    /// Bounds so an enormous field (a whole document) can't hang the app while
    /// we ask for one bounding box per character.
    private static let maxOccurrences = HintLabels.maxCount
    private static let timeBudget: TimeInterval = 0.5
    private static let maxLeafNodes = 4000

    /// The focused text field, if the frontmost app has one whose caret we can
    /// move. Returns nil for non-text focus or read-only text (a rendered
    /// article), where placing a cursor is meaningless.
    static func focused() -> Focus? {
        guard let element = focusedElement(), caretIsSettable(element),
              let value = stringValue(of: element) else {
            return nil
        }
        return Focus(element: element, value: value)
    }

    /// Every visible occurrence of `character` in the focused field, each with a
    /// screen rect for its badge. Tries the native path (bounds on the field
    /// itself) first and falls back to the leaf-node path for web content.
    static func occurrences(
        of character: Character, in value: String, element: AXUIElement, within window: CGRect
    ) -> [Occurrence] {
        let native = nativeOccurrences(of: character, in: value, element: element, within: window)
        if !native.isEmpty { return native }
        return leafOccurrences(of: character, element: element, within: window)
    }

    /// Places the caret just before the matched character.
    static func setCursor(_ element: AXUIElement, to caret: Caret) {
        switch caret {
        case .offset(let offset):
            var range = CFRange(location: offset, length: 0)
            guard let value = AXValueCreate(.cfRange, &range) else { return }
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        case .click(let point):
            MouseClicker.click(at: point, button: .left)
        }
    }

    // MARK: - Native (AppKit) path

    private static func nativeOccurrences(
        of character: Character, in value: String, element: AXUIElement, within window: CGRect
    ) -> [Occurrence] {
        let start = Date()
        var result: [Occurrence] = []
        for offset in TextMatches.offsets(of: character, in: value) {
            if result.count >= maxOccurrences { break }
            if Date().timeIntervalSince(start) > timeBudget { break }
            guard let rect = boundsForRange(element, CFRange(location: offset, length: 1)),
                  !rect.isEmpty, rect.intersects(window) else { continue }
            result.append(Occurrence(rect: rect.intersection(window), caret: .offset(offset)))
        }
        return result
    }

    // MARK: - Web (leaf-node) path

    /// Chromium/Electron editable fields return garbage from `AXBoundsForRange`,
    /// but the character geometry is intact on their nested leaf `AXStaticText`
    /// nodes. Walk those leaves, read per-character bounds from each, and place
    /// the caret with a click since the container's offset space isn't reliable.
    private static func leafOccurrences(
        of character: Character, element: AXUIElement, within window: CGRect
    ) -> [Occurrence] {
        let start = Date()
        var result: [Occurrence] = []
        for leaf in textLeaves(under: element) {
            if result.count >= maxOccurrences { break }
            if Date().timeIntervalSince(start) > timeBudget { break }
            guard let text = stringValue(of: leaf) else { continue }
            for offset in TextMatches.offsets(of: character, in: text) {
                if result.count >= maxOccurrences { break }
                guard let rect = boundsForRange(leaf, CFRange(location: offset, length: 1)),
                      !rect.isEmpty, rect.intersects(window) else { continue }
                // Click the left edge of the glyph so the caret lands before it.
                let point = CGPoint(x: rect.minX + max(1, rect.width * 0.25), y: rect.midY)
                result.append(Occurrence(rect: rect.intersection(window), caret: .click(point)))
            }
        }
        return result
    }

    /// Depth-first leaf text nodes under `element`, in reading order: elements
    /// with no children that carry a non-empty string value (or are AXStaticText).
    private static func textLeaves(under element: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var stack = childElements(of: element).reversed().map { $0 }
        var visited = 0
        while let node = stack.popLast(), result.count < maxOccurrences, visited < maxLeafNodes {
            visited += 1
            let children = childElements(of: node)
            if children.isEmpty {
                let value = stringValue(of: node)
                let role = copyAttribute(node, kAXRoleAttribute) as? String
                if value?.isEmpty == false || role == "AXStaticText" {
                    result.append(node)
                }
            } else {
                stack.append(contentsOf: children.reversed())
            }
        }
        return result
    }

    // MARK: - AX plumbing

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        if let element = axElement(of: system, kAXFocusedUIElementAttribute) {
            return element
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return axElement(of: axApp, kAXFocusedUIElementAttribute)
    }

    private static func axElement(of parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(parent, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement) // swiftlint:disable:this force_cast
    }

    private static func childElements(of element: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttribute(element, kAXChildrenAttribute),
              let array = value as? [AnyObject] else {
            return []
        }
        return array.compactMap {
            CFGetTypeID($0) == AXUIElementGetTypeID()
                ? ($0 as! AXUIElement) // swiftlint:disable:this force_cast
                : nil
        }
    }

    /// Whether the caret can be moved on this element — a reliable proxy for
    /// "this is an editable field". Native fields expose `AXSelectedTextRange`;
    /// web fields expose `AXSelectedTextMarkerRange`.
    private static func caretIsSettable(_ element: AXUIElement) -> Bool {
        isSettable(element, kAXSelectedTextRangeAttribute)
            || isSettable(element, "AXSelectedTextMarkerRange")
    }

    private static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, attribute as CFString, &settable)
        return error == .success && settable.boolValue
    }

    private static func stringValue(of element: AXUIElement) -> String? {
        copyAttribute(element, kAXValueAttribute) as? String
    }

    /// The screen rect of a character range, in AX (top-left global) coordinates.
    /// Correct when asked on a native field or on a web leaf `AXStaticText`.
    private static func boundsForRange(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range),
              let value = copyParameterized(element, kAXBoundsForRangeParameterizedAttribute, rangeValue),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { // swiftlint:disable:this force_cast
            return nil
        }
        return rect
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func copyParameterized(
        _ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, attribute as CFString, parameter, &value
        ) == .success else {
            return nil
        }
        return value
    }
}
