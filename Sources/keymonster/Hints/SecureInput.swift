import AppKit
import Carbon.HIToolbox

/// Detects Secure Keyboard Entry, macOS's anti-keylogging state: while any
/// process holds it, the window server delivers keystrokes only to the focused
/// app and event taps see nothing. Key Monster's focus-based capture
/// (`HintKeyPanel`) is the key window while a mode runs, so the modes are
/// unaffected — this reading feeds the Secure Keyboard Entry window
/// (`SecureInputMonitor`), which narrates the state for debugging *other*
/// apps' key troubles (password prompts hold it briefly; Terminal's toggle
/// and a long-running Music.app are known to hold it indefinitely).
@MainActor
enum SecureInput {
    /// A point-in-time reading of the secure-input state and who — supposedly —
    /// holds it. Pure data so the attribution logic below is unit-testable.
    struct Snapshot: Equatable {
        var enabled: Bool
        var holderPID: Int?
        var holderName: String?
        var holderBundleID: String?
        var frontmostPID: pid_t?
        var frontmostName: String?
        var screenLocked: Bool

        static let free = Snapshot(
            enabled: false, holderPID: nil, holderName: nil, holderBundleID: nil,
            frontmostPID: nil, frontmostName: nil, screenLocked: false
        )

        /// Whether the reported holder pid is just the frontmost app. This is the
        /// common, misleading case: `kCGSSessionSecureInputPID` names the app
        /// currently *receiving* secure input (the frontmost one), NOT the process
        /// that enabled it, and it changes as focus changes. Verified empirically
        /// 2026-08-01: a background process held it continuously while the reported
        /// pid tracked whichever app was foregrounded.
        var holderIsFrontmost: Bool {
            guard let holderPID, let frontmostPID else { return false }
            return Int(frontmostPID) == holderPID
        }

        /// A holder name we're willing to show as the culprit — only when it's a
        /// process distinct from the frontmost app and the screen isn't locked.
        /// Otherwise nil: naming the frontmost app (or `loginwindow` while locked)
        /// blames a red herring, which is exactly the confusion we're avoiding.
        var attributableHolderName: String? {
            guard enabled, !screenLocked, !holderIsFrontmost, let holderName else { return nil }
            return holderName
        }
    }

    /// Read the current secure-input state and the (unreliable) reported holder.
    static func current() -> Snapshot {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let locked = frontmost?.bundleIdentifier == "com.apple.loginwindow"

        guard IsSecureEventInputEnabled() else {
            return Snapshot(
                enabled: false, holderPID: nil, holderName: nil, holderBundleID: nil,
                frontmostPID: frontmost?.processIdentifier, frontmostName: frontmost?.localizedName,
                screenLocked: locked
            )
        }

        let pid = (CGSessionCopyCurrentDictionary() as? [String: Any])?["kCGSSessionSecureInputPID"] as? Int
        let holder = (pid).flatMap { $0 > 0 ? NSRunningApplication(processIdentifier: pid_t($0)) : nil }
        return Snapshot(
            enabled: true, holderPID: pid, holderName: holder?.localizedName,
            holderBundleID: holder?.bundleIdentifier,
            frontmostPID: frontmost?.processIdentifier, frontmostName: frontmost?.localizedName,
            screenLocked: locked
        )
    }

}
