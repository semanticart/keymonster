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
@MainActor
enum AXFocusedText {
    struct Focus {
        let element: AXUIElement
        /// The field's full text at the moment the mode activated.
        let value: String
    }

    /// One on-screen occurrence of the target character.
    struct Occurrence {
        /// UTF-16 offset of the character within the field's value.
        let offset: Int
        /// The character's bounding box in AX (global, top-left origin)
        /// coordinates, clipped to the window.
        let rect: CGRect
    }

    /// Bounds so an enormous field (a whole document) can't hang the app while
    /// we ask for one bounding box per occurrence.
    private static let maxOccurrences = HintLabels.maxCount
    private static let timeBudget: TimeInterval = 0.5

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

    /// The deepest focused element. The system-wide query is the usual path;
    /// some apps only answer it on their own application element, so fall back
    /// to the frontmost app's focused element.
    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        if let element = axElement(of: system, kAXFocusedUIElementAttribute) {
            return element
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return axElement(of: axApp, kAXFocusedUIElementAttribute)
    }

    /// Every visible occurrence of `character` in `value`, each with a screen
    /// rect for its badge. Capped and time-budgeted; occurrences past the cap
    /// or scrolled out of `window` are dropped.
    static func occurrences(
        of character: Character, in value: String, element: AXUIElement, within window: CGRect
    ) -> [Occurrence] {
        let start = Date()
        var result: [Occurrence] = []
        for offset in TextMatches.offsets(of: character, in: value) {
            if result.count >= maxOccurrences { break }
            if Date().timeIntervalSince(start) > timeBudget { break }
            guard let rect = bounds(of: element, offset: offset),
                  !rect.isEmpty, rect.intersects(window) else { continue }
            result.append(Occurrence(offset: offset, rect: rect.intersection(window)))
        }
        return result
    }

    /// Places a zero-length selection at `offset`, i.e. the caret just before
    /// that character.
    static func setCursor(_ element: AXUIElement, to offset: Int) {
        var range = CFRange(location: offset, length: 0)
        guard let value = AXValueCreate(.cfRange, &range) else { return }
        AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
    }

    // MARK: - AX plumbing

    private static func axElement(of parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement) // swiftlint:disable:this force_cast
    }

    /// Whether the caret can be moved on this element — the exact capability
    /// text-jump needs, and a reliable proxy for "this is an editable field".
    private static func caretIsSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(
            element, kAXSelectedTextRangeAttribute as CFString, &settable
        )
        return error == .success && settable.boolValue
    }

    private static func stringValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let string = value as? String else {
            return nil
        }
        return string
    }

    /// The screen rect of the single character at `offset`, via the
    /// parameterized bounds-for-range attribute (supported by native text views
    /// and by WebKit/Chromium text areas).
    private static func bounds(of element: AXUIElement, offset: Int) -> CGRect? {
        var range = CFRange(location: offset, length: 1)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &result
        ) == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect) else { // swiftlint:disable:this force_cast
            return nil
        }
        return rect
    }
}
