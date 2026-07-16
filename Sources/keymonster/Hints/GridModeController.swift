import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "grid")

/// Keyboard-driven clicking anywhere in the frontmost window: a hotkey overlays
/// a grid mirroring the US keyboard's letter rows on the window, and each
/// keypress zooms into the cell in that key's position. After two zooms the
/// next keypress clicks its cell; Return clicks the center of the current
/// region at any point. Shift on the deciding key right-clicks instead; Delete
/// zooms back out; Escape, a real click, or any non-grid keystroke dismisses.
@MainActor
final class GridModeController {
    private let overlay = GridOverlay()
    private let keyTap = HintKeyTap()

    /// Regions zoomed into so far, in AX coordinates: first is the whole
    /// window, last is the active region. Empty while the mode is inactive.
    private var regions: [CGRect] = []

    var isActive: Bool { !regions.isEmpty }

    init() {
        keyTap.acceptsEnter = true
        keyTap.extraCharacters = Set(GridDivision.rows.joined().filter { !$0.isLetter })
            .union(GridDivision.shiftedAliases.keys)
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
            log.info("grid mode needs Accessibility; prompting")
            Paster.requestAccess()
            return
        }
        guard let windowFrame = AXHintTargetFinder.focusedWindowFrame(), !windowFrame.isEmpty else {
            log.info("no focused window for grid mode")
            NSSound.beep()
            return
        }
        guard keyTap.start() else {
            log.error("could not create event tap (Accessibility revoked?)")
            NSSound.beep()
            return
        }

        regions = [windowFrame]
        overlay.show(windowFrame: windowFrame, current: windowFrame)
        log.debug("grid mode active over \(windowFrame.debugDescription)")
    }

    private func handle(_ key: HintKeyEvent) {
        guard let current = regions.last else { return }
        switch key {
        case .escape, .cancel:
            dismiss()
        case .backspace:
            if regions.count > 1 {
                regions.removeLast()
                overlay.update(current: regions[regions.count - 1])
            }
        case .enter(let shifted):
            click(at: CGPoint(x: current.midX, y: current.midY), shifted: shifted)
        case .letter(let letter, let shifted):
            guard let cell = GridDivision.cell(of: current, for: letter) else {
                NSSound.beep()
                return
            }
            if regions.count <= GridDivision.maxShrinks {
                regions.append(cell)
                overlay.update(current: cell)
            } else {
                // Already zoomed in twice: this keypress picks the final spot.
                click(at: CGPoint(x: cell.midX, y: cell.midY), shifted: shifted)
            }
        }
    }

    private func click(at point: CGPoint, shifted: Bool) {
        dismiss()
        // Give the overlay a beat to leave the screen before the click lands.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            MouseClicker.click(at: point, button: shifted ? .right : .left)
        }
    }

    private func dismiss() {
        keyTap.stop()
        overlay.hide()
        regions = []
    }
}
