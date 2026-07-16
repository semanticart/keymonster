import AppKit
import ApplicationServices

/// Keyboard-driven caret placement inside the focused text field (native or
/// web). A hotkey arms the mode; the next key names a target character, every
/// on-screen occurrence of it gets a short label, and typing a label drops the
/// caret just before that character.
///
/// Occurrences too close together to label individually share one green area
/// label; typing it zooms into that area, where each occurrence gets a normal
/// label. Delete backs out of the zoom, then out of the labels to pick a
/// different character; Escape, a real click, or any non-hint keystroke
/// dismisses.
///
/// All label/zoom rules live in `LabelSession`; this controller only reads the
/// field, feeds keystrokes in, and turns the resulting effects into overlay
/// updates and caret moves.
@MainActor
final class TextJumpController {
    /// The focused field captured when the mode armed.
    private struct Field {
        let element: AXUIElement
        let value: String
        let windowFrame: CGRect
    }

    /// The mode's whole life as one value: transitions are single assignments,
    /// and a phase can't carry stale leftovers from another.
    private enum Phase {
        case inactive
        /// Waiting for the keystroke that names the target character.
        case armed(Field)
        /// Labels are on screen; `hits` are what `labels` commits index into.
        case labeling(Field, hits: [AXFocusedText.Occurrence], labels: LabelSession)
    }

    private let overlay = HintOverlay()
    private let keyTap = HintKeyTap()
    private var phase: Phase = .inactive

    var isActive: Bool {
        if case .inactive = phase { return false }
        return true
    }

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

        let field = Field(element: focus.element, value: focus.value, windowFrame: windowFrame)
        phase = .armed(field)
        // Confirm the mode is armed and prompt for the target character; the
        // labels replace this banner once a character is chosen.
        overlay.showBanner("Jump to a character…", windowFrame: windowFrame)
    }

    private func handle(_ key: HintKeyEvent) {
        switch phase {
        case .inactive:
            break
        case .armed(let field):
            handleCharacter(key, field: field)
        case .labeling(let field, let hits, let labels):
            handleLabel(key, field: field, hits: hits, labels: labels)
        }
    }

    /// First phase: the keystroke names the character to jump to.
    private func handleCharacter(_ key: HintKeyEvent, field: Field) {
        switch key {
        case .escape, .cancel, .enter:
            dismiss()
        case .backspace:
            break // nothing typed yet; ignore
        case .letter(let character, _):
            showLabels(for: character, field: field)
        }
    }

    /// Second phase: the keystrokes spell a label — a group label first, then a
    /// member label if the group opened a zoom.
    private func handleLabel(
        _ key: HintKeyEvent, field: Field,
        hits: [AXFocusedText.Occurrence], labels: LabelSession
    ) {
        var labels = labels
        let effect: LabelSession.Effect
        switch key {
        case .escape, .cancel, .enter:
            dismiss()
            return
        case .backspace:
            effect = labels.backspace()
        case .letter(let character, _):
            // Labels are lowercase letters; the raw keystroke may be shifted or
            // otherwise, so fold it before matching.
            let letter = Character(String(character).lowercased())
            effect = labels.type(letter, shifted: false)
        }
        // Store the advanced session before acting on the effect: a commit
        // dismisses, and dismissal must win over this write-back.
        phase = .labeling(field, hits: hits, labels: labels)
        switch effect {
        case .commit(let index, _):
            placeCursor(to: hits[index].caret, element: field.element)
        case .unwound:
            backToCharacterPick(field)
        default:
            overlay.apply(effect)
        }
    }

    private func showLabels(for character: Character, field: Field) {
        let occurrences = AXFocusedText.occurrences(
            of: character, in: field.value, element: field.element, within: field.windowFrame
        )
        guard !occurrences.isEmpty else {
            // No visible match; stay armed so another character can be tried.
            NSSound.beep()
            return
        }
        // Badges may go anywhere on the window's screen; see HintScreens.
        let labels = LabelSession(
            anchors: occurrences.map(\.rect),
            windowFrame: field.windowFrame,
            screenBounds: HintScreens.bounds(around: field.windowFrame),
            badgeSize: BadgeMetrics.size(forLabelLength:)
        )
        phase = .labeling(field, hits: occurrences, labels: labels)
        overlay.show(
            groups: labels.groups, labels: labels.groupLabels, windowFrame: field.windowFrame
        )
    }

    /// Drops the labels and returns to waiting for a target character, keeping
    /// the field session alive.
    private func backToCharacterPick(_ field: Field) {
        phase = .armed(field)
        overlay.showBanner("Jump to a character…", windowFrame: field.windowFrame)
    }

    private func placeCursor(to caret: AXFocusedText.Caret, element: AXUIElement) {
        dismiss()
        AXFocusedText.setCursor(element, to: caret)
    }

    private func dismiss() {
        keyTap.stop()
        overlay.hide()
        phase = .inactive
    }
}
