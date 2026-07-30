import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "scroll")

/// Keyboard-driven scrolling. A hotkey outlines every scrollable pane in the
/// frontmost window with a letter badge; typing a pane's letter activates it,
/// and j/k then scroll it line by line (hold for key repeat). A lone pane skips
/// the pick and scrolls immediately. The active pane keeps its outline, re-read
/// from the accessibility tree as scrolling proceeds so it tracks the pane if
/// it moves — and stands down if the pane disappears. Delete returns to the
/// pane pick; Escape, a real click, or any non-scroll keystroke dismisses.
@MainActor
final class ScrollModeController {
    /// Everything one activation owns; the pane list survives into scrolling so
    /// Delete can reopen the pick.
    private struct Session {
        var panes: [ScrollPane]
        let windowFrame: CGRect
    }

    private enum Phase {
        case inactive
        /// Badged panes are on screen, waiting for a letter.
        case selecting(Session, HintSelection)
        /// `index` names the pane in the session that j/k drive.
        case scrolling(Session, index: Int)
    }

    private let overlay = HintOverlay()
    private let keyTap = HintKeyTap()
    private var phase: Phase = .inactive

    var isActive: Bool {
        if case .inactive = phase { return false }
        return true
    }

    init() {
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
            log.info("scroll mode needs Accessibility; prompting")
            Paster.requestAccess()
            return
        }
        guard let scan = AXScrollPaneFinder.scan() else {
            NSSound.beep()
            return
        }
        let session = Session(panes: scan.panes, windowFrame: scan.windowFrame)
        switch ScrollActivation.forPaneCount(scan.panes.count) {
        case .none:
            log.info("no scrollable panes in the frontmost window")
            NSSound.beep()
        case .scroll(let index):
            guard keyTap.start() else { return tapFailed() }
            startScrolling(session, index: index)
        case .select:
            guard keyTap.start() else { return tapFailed() }
            startSelecting(session)
        }
    }

    private func tapFailed() {
        log.error("could not create event tap (Accessibility revoked?)")
        NSSound.beep()
    }

    private func startSelecting(_ session: Session) {
        let labels = HintLabels.labels(count: session.panes.count)
        phase = .selecting(session, HintSelection(labels: labels))
        overlay.showPanes(
            zip(session.panes, labels).map { (rect: visibleRect(of: $0, in: session), label: $1) },
            windowFrame: session.windowFrame
        )
        log.debug("scroll mode picking among \(session.panes.count) panes")
    }

    private func startScrolling(_ session: Session, index: Int) {
        phase = .scrolling(session, index: index)
        showActivePane(session, index: index)
        log.debug("scrolling pane \(index) of \(session.panes.count)")
    }

    private func showActivePane(_ session: Session, index: Int) {
        overlay.showPanes(
            [(rect: visibleRect(of: session.panes[index], in: session), label: nil)],
            windowFrame: session.windowFrame,
            banner: "J/K to scroll · Esc to stop"
        )
    }

    /// Badges, outlines, and the scroll point all aim at the part of the pane
    /// actually on the window, not the full extent of a pane that hangs off it.
    private func visibleRect(of pane: ScrollPane, in session: Session) -> CGRect {
        pane.frame.intersection(session.windowFrame)
    }

    private func handle(_ key: HintKeyEvent) {
        switch phase {
        case .inactive:
            break
        case .selecting(let session, let selection):
            handlePick(key, session: session, selection: selection)
        case .scrolling(let session, let index):
            handleScroll(key, session: session, index: index)
        }
    }

    private func handlePick(_ key: HintKeyEvent, session: Session, selection: HintSelection) {
        var selection = selection
        switch key {
        case .escape, .cancel, .enter:
            dismiss()
        case .backspace:
            selection.backspace()
            phase = .selecting(session, selection)
            overlay.update(typed: selection.typed)
        case .letter(let letter, _):
            switch selection.type(letter) {
            case .matched(let index):
                startScrolling(session, index: index)
            case .pending:
                phase = .selecting(session, selection)
                overlay.update(typed: selection.typed)
            case .rejected:
                NSSound.beep()
            }
        }
    }

    private func handleScroll(_ key: HintKeyEvent, session: Session, index: Int) {
        switch key {
        case .escape, .cancel, .enter:
            dismiss()
        case .backspace:
            // Back to the pick — unless it was skipped for being a lone pane,
            // in which case there's nothing to go back to.
            if session.panes.count > 1 {
                startSelecting(session)
            }
        case .letter(let letter, _):
            guard let pixels = ScrollWheel.pixels(for: letter) else {
                NSSound.beep()
                return
            }
            let rect = visibleRect(of: session.panes[index], in: session)
            ScrollWheel.scroll(pixels: pixels, at: CGPoint(x: rect.midX, y: rect.midY))
            refreshOutline(session, index: index)
        }
    }

    /// Keeps the outline honest while scrolling: panes rarely move, but ones
    /// that do (a collapsing sidebar, a closing sheet) drag their outline
    /// along, and a pane that vanished ends the mode instead of scrolling
    /// blind.
    private func refreshOutline(_ session: Session, index: Int) {
        var session = session
        guard let frame = AXScrollPaneFinder.currentFrame(of: session.panes[index]),
              ScrollPaneFilter.isUsable(visible: frame.intersection(session.windowFrame)) else {
            dismiss()
            return
        }
        guard frame != session.panes[index].frame else { return }
        session.panes[index].frame = frame
        phase = .scrolling(session, index: index)
        showActivePane(session, index: index)
    }

    private func dismiss() {
        keyTap.stop()
        overlay.hide()
        phase = .inactive
    }
}
