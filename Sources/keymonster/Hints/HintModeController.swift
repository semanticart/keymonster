import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints")

/// Vimium-style click hints: pressing a hint shortcut overlays short labels on
/// everything clickable in the frontmost window (native controls and web
/// content alike); typing a label clicks it.
///
/// Targets too close together to label individually share one green area
/// label; typing it zooms into that area, where each target gets a normal
/// label. Backspace steps back out of the zoom.
///
/// The shortcut's mode picks the button, and holding Shift on the final letter
/// clicks with the opposite one. Escape, a real click, or any non-hint
/// keystroke dismisses the overlay.
///
/// All label/zoom rules live in `LabelSession`; this controller only scans
/// targets, feeds keystrokes in, and turns the resulting effects into overlay
/// updates and clicks.
@MainActor
final class HintModeController {
    /// Everything one activation owns; nil while the mode is inactive, so
    /// dismissal is a single assignment.
    private struct Session {
        let button: MouseClicker.Button
        let targets: [HintTarget]
        /// The app that was frontmost, for terminal links it must open.
        let app: NSRunningApplication?
        var labels: LabelSession
    }

    private let overlay = HintOverlay()
    private let keyInput = HintKeyPanel()
    private var session: Session?
    private var noticeTask: Task<Void, Never>?

    var isActive: Bool { session != nil }

    /// The user's file-path script, from Settings; injectable for tests.
    var filePathScript: String { AppSettings.shared.filePathScript.trimmingCharacters(in: .whitespaces) }

    init() {
        keyInput.handler = { [weak self] key in self?.handle(key) }
    }

    /// Fired by the global hotkeys. Pressing the active mode's shortcut again
    /// dismisses; pressing the other mode's shortcut switches button.
    func toggle(button: MouseClicker.Button) {
        if let session {
            let switching = button != session.button
            dismiss()
            guard switching else { return }
        }
        activate(button: button)
    }

    private func activate(button: MouseClicker.Button) {
        guard Paster.isTrusted else { Paster.requestAccess(); return }
        // Terminals draw their text themselves, so the AX scan finds none of
        // its links; kitty's are read from its screen text instead.
        noticeTask?.cancel()
        let scan = AXHintTargetFinder.scan()
        let frontmost = NSWorkspace.shared.frontmostApplication
        let findFiles = !filePathScript.isEmpty
        let terminal = frontmost.map { KittyLinkScanner.scan($0, findFiles: findFiles) }
            ?? KittyLinkScanner.Outcome()
        let found = (scan?.targets ?? []) + terminal.targets
        guard let windowFrame = scan?.windowFrame, !found.isEmpty else {
            log.info("no hint targets in the frontmost window")
            NSSound.beep()
            if let issue = terminal.issue, let frame = scan?.windowFrame {
                flashNotice("Kitty link hints: \(issue.detail)", over: frame)
            }
            return
        }
        guard keyInput.start() else {
            log.error("could not take key focus for hint input")
            NSSound.beep()
            return
        }

        // More targets than two-letter labels exist: drop the overflow.
        let targets = Array(found.prefix(HintLabels.maxCount))
        // Badges may go anywhere on the window's screen, so labels for
        // elements at the window's edge hang just outside it instead of
        // crowding (and clustering) within.
        let labels = LabelSession(
            anchors: targets.map(\.frame),
            windowFrame: windowFrame,
            screenBounds: HintScreens.bounds(around: windowFrame),
            badgeSize: BadgeMetrics.size(forLabelLength:)
        )
        session = Session(button: button, targets: targets, app: frontmost, labels: labels)
        // Hints may still exist (a titlebar's buttons) when kitty's links
        // couldn't be read; say so rather than letting them look like all there is.
        overlay.show(
            groups: labels.groups, labels: labels.groupLabels, windowFrame: windowFrame,
            banner: terminal.issue.map { "Kitty link hints: \($0.detail)" }
        )
        log.debug(
            "hint mode active with \(targets.count) targets in \(labels.groups.count) groups"
        )
        logClusters()
    }

    /// Dumps every cluster's area and member frames, for chasing layout
    /// surprises like a wash far wider than the targets it stands for.
    private func logClusters() {
        guard let session else { return }
        func describe(_ rect: CGRect) -> String {
            "(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height)))"
        }
        for (group, label) in zip(session.labels.groups, session.labels.groupLabels)
        where group.isCluster {
            let members = group.members
                .map { "\(session.targets[$0].role ?? "?") \(describe(session.targets[$0].frame))" }
                .joined(separator: ", ")
            log.debug(
                """
                cluster \(label.uppercased(), privacy: .public): \
                area \(describe(group.area), privacy: .public) \
                members [\(members, privacy: .public)]
                """
            )
        }
    }

    private func handle(_ key: HintKeyEvent) {
        guard session != nil else { return }
        switch key {
        case .escape, .cancel:
            dismiss()
        case .enter:
            // Hint mode leaves the tap's `acceptsEnter` off, so Return never
            // arrives here; dismissing is the sane fallback if it somehow does.
            dismiss()
        case .backspace:
            apply(session?.labels.backspace())
        case .letter(let letter, let shifted):
            apply(session?.labels.type(letter, shifted: shifted))
        }
    }

    private func apply(_ effect: LabelSession.Effect?) {
        guard let effect else { return }
        switch effect {
        case .commit(let index, let shifted):
            guard let session else { return }
            let target = session.targets[index]
            let button = shifted ? session.button.opposite : session.button
            dismiss()
            if let file = target.file {
                KittyLinkScanner.open(file, script: filePathScript)
                return
            }
            if let url = target.linkURL, let app = session.app {
                KittyLinkScanner.open(url, in: app)
                return
            }
            MouseClicker.clickOnceOverlaySettles(at: target.clickPoint, button: button)
        case .unwound:
            break // nothing typed and no zoom: backspace has nothing to undo
        case .zoomIn:
            // Zoom magnifies a screenshot; without Screen Recording there is
            // nothing meaningful to show, so drop the mode and let the prompt
            // (or Settings alert) take over.
            guard WindowCapture.ensureAccess() else {
                dismiss()
                return
            }
            overlay.apply(effect)
        default:
            overlay.apply(effect)
        }
    }

    /// Says why nothing was hinted, for a few seconds, over the window. For
    /// failures the user can fix (a terminal that isn't set up), where a bare
    /// beep would leave them guessing.
    private func flashNotice(_ text: String, over windowFrame: CGRect) {
        overlay.showBanner(text, windowFrame: windowFrame)
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, self.session == nil else { return }
            self.overlay.hide()
        }
    }

    private func dismiss() {
        keyInput.stop()
        overlay.hide()
        session = nil
    }
}
