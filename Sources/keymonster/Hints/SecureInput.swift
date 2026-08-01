import AppKit
import Carbon.HIToolbox
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints.secureinput")

/// Detects Secure Keyboard Entry, macOS's anti-keylogging state: while any
/// process holds it, the window server delivers keystrokes only to the focused
/// app and event taps see nothing. A hint mode started then would draw its
/// overlay and watch every letter sail through to the target app (password
/// prompts hold it briefly; Terminal's "Secure Keyboard Entry" and a
/// long-running Music.app are known to hold it indefinitely).
@MainActor
enum SecureInput {
    /// When secure input is on, names the app holding it, beeps, and flashes
    /// an explanatory banner over `windowFrame` — the caller should not start
    /// its key tap. Returns false when input is free.
    static func blocksHintInput(windowFrame: CGRect) -> Bool {
        guard IsSecureEventInputEnabled() else { return false }
        let name = holderName() ?? "Another app"
        log.error("secure keyboard entry is on (held by \(name)); keys can't be intercepted")
        HintOverlay.flash(
            "\(name) is holding Secure Keyboard Entry — keys can't reach Key Monster",
            windowFrame: windowFrame
        )
        NSSound.beep()
        return true
    }

    /// The display name of the process holding secure input, from the session
    /// dictionary's undocumented-but-stable secure-input pid entry.
    private static func holderName() -> String? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = session["kCGSSessionSecureInputPID"] as? Int else {
            return nil
        }
        return NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName
            ?? "A process (pid \(pid))"
    }
}
