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
@MainActor
final class TextJumpController {
    private let overlay = HintOverlay()
    private let keyTap = HintKeyTap()

    // Session state, non-nil only while the mode is active.
    private var element: AXUIElement?
    private var value = ""
    private var windowFrame: CGRect = .zero

    // Label state, non-nil only once a character has been picked and its
    // occurrences are on screen. Groups map label indices to `hits`.
    private var hits: [AXFocusedText.Occurrence] = []
    private var groups: [HintGrouping.Group] = []
    private var groupLabels: [String] = []
    private var zoomed: HintGrouping.Group?
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

    /// Second phase: the keystrokes spell a label — a group label first, then a
    /// member label if the group opened a zoom.
    private func handleLabel(_ key: HintKeyEvent) {
        switch key {
        case .escape, .cancel, .enter:
            dismiss()
        case .backspace:
            if !(selection?.typed.isEmpty ?? true) {
                selection?.backspace()
                overlay.update(typed: selection?.typed ?? "")
            } else if zoomed != nil {
                exitZoom()
            } else {
                backToCharacterPick()
            }
        case .letter(let character, _):
            // Labels are lowercase letters; the raw keystroke may be shifted or
            // otherwise, so fold it before matching.
            let letter = Character(String(character).lowercased())
            switch selection?.type(letter) {
            case .matched(let index):
                pick(index)
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
        hits = occurrences
        // Badges may go anywhere on the window's screen; see HintScreens.
        (groups, groupLabels) = HintGrouping.groupsWithLabels(
            anchors: occurrences.map(\.rect),
            within: HintScreens.bounds(around: windowFrame),
            badgeSize: HintOverlayView.badgeSize(forLabelLength:)
        )
        selection = HintSelection(labels: groupLabels)
        overlay.show(groups: groups, labels: groupLabels, windowFrame: windowFrame)
    }

    /// A full label was typed: inside the zoom it names an occurrence; outside
    /// it names a group, which either places the caret (single) or zooms in
    /// (cluster).
    private func pick(_ index: Int) {
        if let zoomed {
            placeCursor(to: hits[zoomed.members[index]].caret)
        } else if groups[index].isCluster {
            enterZoom(groups[index])
        } else {
            placeCursor(to: hits[groups[index].members[0]].caret)
        }
    }

    private func enterZoom(_ group: HintGrouping.Group) {
        zoomed = group
        let memberFrames = group.members.map { hits[$0].rect }
        let labels = HintLabels.labels(count: memberFrames.count)
        selection = HintSelection(labels: labels)
        // A little context around the characters, kept on the window.
        let area = group.area.insetBy(dx: -8, dy: -8).intersection(windowFrame)
        overlay.showZoom(
            area: area,
            image: overlay.snapshotBelow(area: area),
            memberFrames: memberFrames,
            labels: labels
        )
    }

    private func exitZoom() {
        zoomed = nil
        selection = HintSelection(labels: groupLabels)
        overlay.clearZoom()
    }

    /// Drops the labels and returns to waiting for a target character, keeping
    /// the field session alive.
    private func backToCharacterPick() {
        hits = []
        groups = []
        groupLabels = []
        zoomed = nil
        selection = nil
        overlay.showBanner("Jump to a character…", windowFrame: windowFrame)
    }

    private func placeCursor(to caret: AXFocusedText.Caret) {
        guard let element else { return }
        dismiss()
        AXFocusedText.setCursor(element, to: caret)
    }

    private func dismiss() {
        keyTap.stop()
        overlay.hide()
        element = nil
        value = ""
        windowFrame = .zero
        hits = []
        groups = []
        groupLabels = []
        zoomed = nil
        selection = nil
    }
}
