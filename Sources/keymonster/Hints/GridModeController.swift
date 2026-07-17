import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "grid")

/// Keyboard-driven clicking anywhere in the frontmost window. A hotkey overlays
/// the initial grid: a fine grid of two-character hint labels (see `GridHints`)
/// covering the window. Type a cell's label and grid mode zooms into it, then
/// each further keypress narrows further — a keyboard-position grid, magnified
/// into a loupe — until, after three zooms, the next keypress clicks. Return
/// clicks the center of the current region at any point. Shift on the deciding
/// key right-clicks instead; Delete steps back out; Escape, a real click, or
/// any non-grid keystroke dismisses.
@MainActor
final class GridModeController {
    private let overlay = GridOverlay()
    private let keyTap = HintKeyTap()

    /// The whole window, in AX coordinates; the base the hint grid covers.
    private var windowFrame: CGRect = .zero
    /// Regions zoomed into so far (AX coordinates): first is always the window,
    /// last is the active region. Empty while grid mode is inactive.
    private var regions: [CGRect] = []
    /// The initial hint grid and its typed-prefix matcher, live only until a
    /// label is picked; nil once the positional grid takes over.
    private var hintCells: [GridHints.Cell] = []
    private var hintSelection: HintSelection?

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

        self.windowFrame = windowFrame
        regions = [windowFrame]
        overlay.present(windowFrame: windowFrame)
        startHintPhase()
        log.debug("grid mode active over \(windowFrame.debugDescription)")
    }

    /// Shows the initial hint grid over the whole window and arms its matcher.
    private func startHintPhase() {
        hintCells = GridHints.cells(of: windowFrame)
        hintSelection = HintSelection(labels: hintCells.map(\.label))
        overlay.showHints(cells: hintCells, typed: "")
    }

    private func handle(_ key: HintKeyEvent) {
        guard let current = regions.last else { return }
        switch key {
        case .escape, .cancel:
            dismiss()
        case .backspace:
            backspace()
        case .enter(let shifted):
            click(at: CGPoint(x: current.midX, y: current.midY), shifted: shifted)
        case .letter(let letter, let shifted):
            if hintSelection != nil {
                pickHint(letter)
            } else {
                zoomOrClick(current: current, letter: letter, shifted: shifted)
            }
        }
    }

    /// A keystroke while the hint grid is up: narrow the matches, or on a full
    /// label commit its cell and hand off to the positional grid.
    private func pickHint(_ letter: Character) {
        guard var selection = hintSelection else { return }
        switch selection.type(letter) {
        case .matched(let index):
            let cell = hintCells[index].rect
            hintSelection = nil
            hintCells = []
            descend(into: cell)
        case .pending:
            hintSelection = selection
            overlay.showHints(cells: hintCells, typed: selection.typed)
        case .rejected:
            NSSound.beep()
        }
    }

    /// A keystroke on a positional grid: zoom into the key's cell, or once the
    /// shrink limit is reached, click it.
    private func zoomOrClick(current: CGRect, letter: Character, shifted: Bool) {
        guard let cell = GridDivision.cell(of: current, for: letter) else {
            NSSound.beep()
            return
        }
        if regions.count <= GridDivision.maxShrinks {
            descend(into: cell, shifted: shifted)
        } else {
            // Already zoomed in the max times: this keypress picks the spot.
            click(at: CGPoint(x: cell.midX, y: cell.midY), shifted: shifted)
        }
    }

    /// Zoom into `region` and show its grid — unless it has collapsed to a
    /// single cell, in which case there's nothing left to disambiguate, so
    /// click its center rather than show a one-cell grid you'd only Return on.
    private func descend(into region: CGRect, shifted: Bool = false) {
        regions.append(region)
        if GridDivision.cells(of: region).count == 1 {
            click(at: CGPoint(x: region.midX, y: region.midY), shifted: shifted)
        } else {
            overlay.showGrid(current: region)
        }
    }

    /// Delete: drop the last typed hint letter, or step back one zoom — landing
    /// back on the initial hint grid when the last zoom is undone.
    private func backspace() {
        if var selection = hintSelection {
            selection.backspace()
            hintSelection = selection
            overlay.showHints(cells: hintCells, typed: selection.typed)
            return
        }
        guard regions.count > 1 else { return }
        regions.removeLast()
        if regions.count == 1 {
            startHintPhase()
        } else {
            overlay.showGrid(current: regions[regions.count - 1])
        }
    }

    private func click(at point: CGPoint, shifted: Bool) {
        dismiss()
        MouseClicker.clickOnceOverlaySettles(at: point, button: shifted ? .right : .left)
    }

    private func dismiss() {
        keyTap.stop()
        overlay.hide()
        regions = []
        hintCells = []
        hintSelection = nil
    }
}
