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
@MainActor
final class HintModeController {
    private let overlay = HintOverlay()
    private let keyTap = HintKeyTap()
    private var selection: HintSelection?
    private var targets: [HintTarget] = []
    private var groups: [HintGrouping.Group] = []
    private var groupLabels: [String] = []
    private var zoomed: HintGrouping.Group?
    private var windowFrame: CGRect = .zero
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
        windowFrame = scan.windowFrame
        // Badges may go anywhere on the window's screen, so labels for
        // elements at the window's edge hang just outside it instead of
        // crowding (and clustering) within.
        (groups, groupLabels) = HintGrouping.groupsWithLabels(
            anchors: targets.map(\.frame),
            within: HintScreens.bounds(around: windowFrame),
            badgeSize: HintOverlayView.badgeSize(forLabelLength:)
        )
        selection = HintSelection(labels: groupLabels)
        overlay.show(groups: groups, labels: groupLabels, windowFrame: windowFrame)
        log.debug("hint mode active with \(self.targets.count) targets in \(self.groups.count) groups")
    }

    private func handle(_ key: HintKeyEvent) {
        guard selection != nil else { return }
        switch key {
        case .escape, .cancel:
            dismiss()
        case .enter:
            // Hint mode leaves the tap's `acceptsEnter` off, so Return never
            // arrives here; dismissing is the sane fallback if it somehow does.
            dismiss()
        case .backspace:
            if zoomed != nil, selection?.typed.isEmpty ?? true {
                exitZoom()
            } else {
                selection?.backspace()
                overlay.update(typed: selection?.typed ?? "")
            }
        case .letter(let letter, let shifted):
            switch selection?.type(letter) {
            case .matched(let index):
                pick(index, shifted: shifted)
            case .pending:
                overlay.update(typed: selection?.typed ?? "")
            case .rejected, nil:
                NSSound.beep()
            }
        }
    }

    /// A full label was typed: inside the zoom it names a member; outside it
    /// names a group, which either clicks (single) or zooms in (cluster).
    private func pick(_ index: Int, shifted: Bool) {
        if let zoomed {
            click(targets[zoomed.members[index]], shifted: shifted)
        } else if groups[index].isCluster {
            enterZoom(groups[index])
        } else {
            click(targets[groups[index].members[0]], shifted: shifted)
        }
    }

    private func enterZoom(_ group: HintGrouping.Group) {
        zoomed = group
        let memberFrames = group.members.map { targets[$0].frame }
        let labels = HintLabels.labels(count: memberFrames.count)
        selection = HintSelection(labels: labels)
        // A little context around the members, kept on the window.
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
        groups = []
        groupLabels = []
        zoomed = nil
        windowFrame = .zero
    }
}
