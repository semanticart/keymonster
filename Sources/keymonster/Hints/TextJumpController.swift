import AppKit
import ApplicationServices

/// Keyboard-driven caret placement inside the focused text field (native or
/// web). A hotkey arms the mode; the next key names a target character, every
/// on-screen occurrence of it gets a short label, and typing a label drops the
/// caret just before that character.
///
/// Delete backs out of the labels to pick a different character; Escape, a real
/// click, or any non-hint keystroke dismisses.
@MainActor
final class TextJumpController {
    private let overlay = HintOverlay()
    private let keyTap = HintKeyTap()

    // Session state, non-nil only while the mode is active.
    private var element: AXUIElement?
    private var value = ""
    private var windowFrame: CGRect = .zero

    // Label state, non-nil only once a character has been picked and its
    // occurrences are on screen. `offsets[i]` is the caret position for label i.
    private var offsets: [Int] = []
    private var selection: HintSelection?

    var isActive: Bool { element != nil }
    private var pickingLabel: Bool { selection != nil }

    init() {
        // The target character can be anything typed — a digit, punctuation, or
        // a space — not just a hint letter, so take keystrokes raw.
        keyTap.reportsRawCharacters = true
        keyTap.handler = { [weak self] key in self?.handle(key) }
    }

    /// Fired by the global hotkey; pressing it again dismisses.
    func toggle() {
        if isActive {
            dismiss()
        } else {
            activate()
        }
    }

    private func activate() {
        guard Paster.isTrusted else {
            Paster.requestAccess()
            return
        }
        guard let focus = AXFocusedText.focused() else {
            NSSound.beep()
            return
        }
        guard let windowFrame = AXHintTargetFinder.focusedWindowFrame(), !windowFrame.isEmpty else {
            NSSound.beep()
            return
        }
        guard keyTap.start() else {
            NSSound.beep()
            return
        }

        element = focus.element
        value = focus.value
        self.windowFrame = windowFrame
        // Confirm the mode is armed and prompt for the target character; the
        // labels replace this banner once a character is chosen.
        overlay.showBanner("Jump to a character…", windowFrame: windowFrame)
    }

    private func handle(_ key: HintKeyEvent) {
        guard isActive else { return }
        if pickingLabel {
            handleLabel(key)
        } else {
            handleCharacter(key)
        }
    }

    /// First phase: the keystroke names the character to jump to.
    private func handleCharacter(_ key: HintKeyEvent) {
        switch key {
        case .escape, .cancel, .enter:
            dismiss()
        case .backspace:
            break // nothing typed yet; ignore
        case .letter(let character, _):
            showLabels(for: character)
        }
    }

    /// Second phase: the keystrokes spell a label, which resolves to a caret
    /// position.
    private func handleLabel(_ key: HintKeyEvent) {
        switch key {
        case .escape, .cancel, .enter:
            dismiss()
        case .backspace:
            if selection?.typed.isEmpty ?? true {
                backToCharacterPick()
            } else {
                selection?.backspace()
                overlay.update(typed: selection?.typed ?? "")
            }
        case .letter(let character, _):
            // Labels are lowercase home-row letters; the raw keystroke may be
            // shifted or otherwise, so fold it before matching.
            let letter = Character(String(character).lowercased())
            switch selection?.type(letter) {
            case .matched(let index):
                placeCursor(at: offsets[index])
            case .pending:
                overlay.update(typed: selection?.typed ?? "")
            case .rejected, nil:
                NSSound.beep()
            }
        }
    }

    private func showLabels(for character: Character) {
        guard let element else { return }
        let occurrences = AXFocusedText.occurrences(
            of: character, in: value, element: element, within: windowFrame
        )
        guard !occurrences.isEmpty else {
            // No visible match; stay armed so another character can be tried.
            NSSound.beep()
            return
        }
        offsets = occurrences.map(\.offset)
        let targets = occurrences.map { HintTarget(frame: $0.rect) }
        let labels = HintLabels.labels(count: targets.count)
        selection = HintSelection(labels: labels)
        overlay.show(targets: targets, labels: labels, windowFrame: windowFrame)
    }

    /// Drops the labels and returns to waiting for a target character, keeping
    /// the field session alive.
    private func backToCharacterPick() {
        offsets = []
        selection = nil
        overlay.showBanner("Jump to a character…", windowFrame: windowFrame)
    }

    private func placeCursor(at offset: Int) {
        guard let element else { return }
        dismiss()
        AXFocusedText.setCursor(element, to: offset)
    }

    private func dismiss() {
        keyTap.stop()
        overlay.hide()
        element = nil
        value = ""
        windowFrame = .zero
        offsets = []
        selection = nil
    }
}
