import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints")

/// Vimium-style click hints: pressing a hint shortcut overlays two-letter
/// labels on everything clickable in the frontmost window (native controls and
/// web content alike); typing a label clicks it.
///
/// The shortcut's mode picks the button, and holding Shift on the final letter
/// clicks with the opposite one. Escape, a real click, or any non-hint
/// keystroke dismisses the overlay.
@MainActor
final class HintModeController {
    private let overlay = HintOverlay()
    private let keyTap = HintKeyTap()
    private var selection: HintSelection?
    private var targets: [HintTarget] = []
    private var button: MouseClicker.Button = .left

    var isActive: Bool { selection != nil }

    init() {
        keyTap.handler = { [weak self] key in self?.handle(key) }
    }

    /// Fired by the global hotkeys. Pressing the active mode's shortcut again
    /// dismisses; pressing the other mode's shortcut switches button.
    func toggle(button: MouseClicker.Button) {
        if isActive {
            let switching = button != self.button
            dismiss()
            guard switching else { return }
        }
        activate(button: button)
    }

    private func activate(button: MouseClicker.Button) {
        guard Paster.isTrusted else {
            log.info("hint mode needs Accessibility; prompting")
            Paster.requestAccess()
            return
        }
        guard let scan = AXHintTargetFinder.scan(), !scan.targets.isEmpty else {
            log.info("no hint targets in the frontmost window")
            NSSound.beep()
            return
        }
        guard keyTap.start() else {
            log.error("could not create event tap (Accessibility revoked?)")
            NSSound.beep()
            return
        }

        self.button = button
        // More targets than two-letter labels exist: drop the overflow.
        targets = Array(scan.targets.prefix(HintLabels.maxCount))
        let labels = HintLabels.labels(count: targets.count)
        selection = HintSelection(labels: labels)
        overlay.show(targets: targets, labels: labels, windowFrame: scan.windowFrame)
        log.debug("hint mode active with \(self.targets.count) targets")
    }

    private func handle(_ key: HintKeyEvent) {
        guard selection != nil else { return }
        switch key {
        case .escape, .cancel:
            dismiss()
        case .backspace:
            selection?.backspace()
            overlay.update(typed: selection?.typed ?? "")
        case .letter(let letter, let shifted):
            switch selection?.type(letter) {
            case .matched(let index):
                click(targets[index], shifted: shifted)
            case .pending:
                overlay.update(typed: selection?.typed ?? "")
            case .rejected, nil:
                NSSound.beep()
            }
        }
    }

    private func click(_ target: HintTarget, shifted: Bool) {
        let point = target.clickPoint
        let clickButton = shifted ? button.opposite : button
        dismiss()
        // Give the overlay a beat to leave the screen before the click lands.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            MouseClicker.click(at: point, button: clickButton)
        }
    }

    private func dismiss() {
        keyTap.stop()
        overlay.hide()
        selection = nil
        targets = []
    }
}
