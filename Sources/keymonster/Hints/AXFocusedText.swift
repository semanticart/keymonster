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
/// The search itself lives in `TextOccurrences`, over the `AXTextTree` protocol;
/// this type is the live tree plus the focus and caret plumbing around it.
@MainActor
enum AXFocusedText {
    struct Focus {
        let element: AXUIElement
        /// The field's full text at the moment the mode activated.
        let value: String
    }

    /// The focused text field, if the frontmost app has one whose caret we can
    /// move. Returns nil for non-text focus or read-only text (a rendered
    /// article), where placing a cursor is meaningless.
    static func focused() -> Focus? {
        armWebAccessibility()
        guard let element = focusedElement(), caretIsSettable(element),
              let value = axString(element, kAXValueAttribute) else {
            return nil
        }
        return Focus(element: element, value: value)
    }

    /// Every visible occurrence of `character` in the focused field, each with a
    /// screen rect for its badge.
    static func occurrences(
        of character: Character, in value: String, element: AXUIElement, within window: CGRect
    ) -> [TextOccurrence] {
        TextSearch(tree: LiveAXTextTree(), window: window, budget: .live())
            .find(character, in: value, element: element)
    }

    /// Places the caret just before the matched character.
    static func setCursor(_ element: AXUIElement, to caret: TextCaret) {
        switch caret {
        case .offset(let offset):
            var range = CFRange(location: offset, length: 0)
            guard let value = AXValueCreate(.cfRange, &range) else { return }
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        case .click(let point):
            // The caller dismissed first, but the overlay's window needs a beat
            // to actually leave the screen — clicking now would land on the
            // departing badges instead of the field. Same reason hint mode
            // clicks its targets this way. Unlike hint mode, the click is only
            // how the caret gets placed, so the pointer goes back afterward.
            MouseClicker.clickOnceOverlaySettlesThenRestorePointer(at: point, button: .left)
        }
    }

    // MARK: - Focus

    /// Browsers and Electron apps only build an accessibility tree for their web
    /// content once an assistive client asks for it, and the leaf-node path is
    /// that tree. `AXHintTargetFinder.scan` asks on hint mode's behalf; text jump
    /// has to ask for itself, or it only sees web fields in apps hint mode
    /// happened to have visited. Apps that don't understand these return an
    /// error, which is fine to ignore.
    private static func armWebAccessibility() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// The deepest focused element. The system-wide query is the usual path;
    /// some apps only answer it on their own application element, so fall back
    /// to the frontmost app's focused element.
    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        if let element = axElement(system, kAXFocusedUIElementAttribute) {
            return element
        }
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return axElement(axApp, kAXFocusedUIElementAttribute)
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
}

/// The live accessibility tree, as `TextOccurrences` reads it. Not isolated:
/// the AX calls are plain C, and keeping the conformance free of an actor lets
/// the search stay pure.
struct LiveAXTextTree: AXTextTree {
    func children(of element: AXUIElement) -> [AXUIElement] {
        guard let value = axCopy(element, kAXChildrenAttribute),
              let array = value as? [AnyObject] else {
            return []
        }
        return array.compactMap {
            CFGetTypeID($0) == AXUIElementGetTypeID()
                ? ($0 as! AXUIElement) // swiftlint:disable:this force_cast
                : nil
        }
    }

    func stringValue(of element: AXUIElement) -> String? {
        axString(element, kAXValueAttribute)
    }

    func role(of element: AXUIElement) -> String? {
        axString(element, kAXRoleAttribute)
    }

    /// Correct when asked on a native field or on a web leaf `AXStaticText`.
    /// Chromium's editable containers answer a degenerate rect here, and its
    /// omnibox doesn't implement the attribute at all — both come back as
    /// something `TextOccurrences` rejects.
    func bounds(of element: AXUIElement, at offset: Int) -> CGRect? {
        var range = CFRange(location: offset, length: 1)
        guard let rangeValue = AXValueCreate(.cfRange, &range),
              let value = axCopyParameterized(
                  element, kAXBoundsForRangeParameterizedAttribute, rangeValue
              ),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { // swiftlint:disable:this force_cast
            return nil
        }
        return rect
    }
}

// MARK: - AX plumbing

private func axElement(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let value = axCopy(parent, attribute),
          CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return (value as! AXUIElement) // swiftlint:disable:this force_cast
}

private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    axCopy(element, attribute) as? String
}

private func axCopy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value
}

private func axCopyParameterized(
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
