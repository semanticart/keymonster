import AppKit

/// One keystroke's meaning while a mode is showing.
enum HintKeyEvent: Equatable {
    case letter(Character, shifted: Bool)
    case escape
    case backspace
    /// Return or keypad Enter. Only produced when the classifier's
    /// `acceptsEnter` is on (grid mode confirms with Return); otherwise Return
    /// falls through to `.cancel` like any other non-hint key.
    case enter(shifted: Bool)
    /// Anything else — a chorded shortcut, a mouse click, cmd-tab. The mode
    /// should get out of the way.
    case cancel
}

/// The keystroke→`HintKeyEvent` rules for `HintKeyPanel`, kept separate so
/// they're pure and testable. Works on `NSEvent`, which does the
/// keycode→character mapping for the user's actual keyboard layout, so hints
/// work on Dvorak/AZERTY too.
struct HintKeyClassifier {
    /// When on, Return/keypad Enter is reported as `.enter` instead of falling
    /// through to `.cancel` (grid mode confirms with Return).
    var acceptsEnter = false
    /// Non-letter characters that still count as input (grid mode's keyboard
    /// rows include punctuation like ";" and "[", plus their shifted forms).
    var extraCharacters: Set<Character> = []
    /// When on, any single printable key is reported verbatim as `.letter`
    /// (un-lowercased, digits and punctuation included) instead of being
    /// filtered to hint letters — text-jump mode's target character can be
    /// anything typed.
    var reportsRawCharacters = false

    /// nil means the keystroke isn't hint input (chorded, non-letter); the
    /// caller reports `.cancel` so the mode dismisses.
    func classify(_ event: NSEvent) -> HintKeyEvent? {
        switch event.keyCode {
        case 53: return .escape
        case 51: return .backspace
        default: break
        }
        let flags = event.modifierFlags
        if acceptsEnter, event.keyCode == 36 || event.keyCode == 76 { // Return, keypad Enter
            return .enter(shifted: flags.contains(.shift))
        }
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return nil
        }
        guard let characters = event.charactersIgnoringModifiers,
              characters.count == 1, let character = characters.first else {
            return nil
        }
        // Text-jump's first phase accepts any printable character (a letter,
        // digit, symbol, or space) as the jump target; control keys like Return
        // and Tab still fall through to `.cancel`.
        if reportsRawCharacters {
            guard let scalar = character.unicodeScalars.first, scalar.value >= 0x20 else {
                return nil
            }
            return .letter(character, shifted: flags.contains(.shift))
        }
        guard let letter = characters.lowercased().first,
              letter.isASCII, letter.isLetter || extraCharacters.contains(letter) else {
            return nil
        }
        return .letter(letter, shifted: flags.contains(.shift))
    }
}
