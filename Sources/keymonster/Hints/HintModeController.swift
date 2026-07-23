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
        var labels: LabelSession
    }

    private let overlay = HintOverlay()
    private let keyTap = HintKeyTap()
    private var session: Session?

    var isActive: Bool { session != nil }

    init() {
        keyTap.handler = { [weak self] key in self?.handle(key) }
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

        // More targets than two-letter labels exist: drop the overflow.
        let targets = Array(scan.targets.prefix(HintLabels.maxCount))
        // Badges may go anywhere on the window's screen, so labels for
        // elements at the window's edge hang just outside it instead of
        // crowding (and clustering) within.
        let labels = LabelSession(
            anchors: targets.map(\.frame),
            windowFrame: scan.windowFrame,
            screenBounds: HintScreens.bounds(around: scan.windowFrame),
            badgeSize: BadgeMetrics.size(forLabelLength:)
        )
        session = Session(button: button, targets: targets, labels: labels)
        overlay.show(
            groups: labels.groups, labels: labels.groupLabels, windowFrame: scan.windowFrame
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

    private func dismiss() {
        keyTap.stop()
        overlay.hide()
        session = nil
    }
}
