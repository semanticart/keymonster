import AppKit
import Carbon.HIToolbox
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints.keyinput")

/// The key-capture front door for hint/grid/scroll/text-jump modes. Owns both
/// backends and picks one per activation from the experimental
/// `focusKeyCapture` setting:
///
///   - `HintKeyTap` (default): a passive CGEvent tap. Invisible to the target
///     app, but starved by Secure Keyboard Entry and requires the Input
///     Monitoring permission on top of Accessibility.
///   - `HintKeyPanel` (experimental): an invisible non-activating key panel.
///     Immune to Secure Keyboard Entry and needs no Input Monitoring, at the
///     cost of briefly owning keyboard focus while a mode is active.
///
/// The permission and secure-input gates live here too, so each controller's
/// activation reads the same regardless of backend.
@MainActor
final class HintKeyInput {
    var handler: ((HintKeyEvent) -> Void)?
    /// See `HintKeyClassifier` — set once by the owning mode, applied to
    /// whichever backend `start()` picks.
    var acceptsEnter = false
    var extraCharacters: Set<Character> = []
    var reportsRawCharacters = false

    private let tap = HintKeyTap()
    private let panel = HintKeyPanel()

    static var usesFocusCapture: Bool { AppSettings.shared.focusKeyCapture }

    /// The permissions gate for a mode activation. Focus capture reads keys via
    /// the responder chain, so it drops the Input Monitoring requirement;
    /// Accessibility is still needed either way for the AX scan and clicks.
    static func ensureAccess() -> Bool {
        KeyTapAccess.ensureGranted(needsInputMonitoring: !usesFocusCapture)
    }

    /// The secure-input gate for a mode activation. Focus capture is the key
    /// window, and Secure Keyboard Entry only starves eavesdroppers — so with
    /// it on, secure input never blocks and the mode proceeds.
    static func secureInputBlocks(windowFrame: CGRect) -> Bool {
        guard !usesFocusCapture else {
            if IsSecureEventInputEnabled() {
                log.info("secure input is on, but focus capture is immune; proceeding")
            }
            return false
        }
        return SecureInput.blocksHintInput(windowFrame: windowFrame)
    }

    /// Starts the backend the setting currently names, with this mode's
    /// classifier rules. Returns false when capture can't begin (tap creation
    /// failed, or the panel was refused key status).
    func start() -> Bool {
        var classifier = HintKeyClassifier()
        classifier.acceptsEnter = acceptsEnter
        classifier.extraCharacters = extraCharacters
        classifier.reportsRawCharacters = reportsRawCharacters
        if Self.usesFocusCapture {
            panel.classifier = classifier
            panel.handler = handler
            return panel.start()
        }
        tap.classifier = classifier
        tap.handler = handler
        return tap.start()
    }

    /// Stops both backends — harmless for the idle one, and correct even if the
    /// setting flipped while a mode was active.
    func stop() {
        tap.stop()
        panel.stop()
    }
}
