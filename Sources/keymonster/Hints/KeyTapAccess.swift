import AppKit
import ApplicationServices
import IOKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "keytapaccess")

/// The TCC permissions the hint/grid/scroll/text-jump key tap depends on, and
/// the prompts for them.
///
/// Two *separate* toggles are involved, and granting one does not grant the
/// other:
///   - Accessibility (`AXIsProcessTrusted`) — lets the active event tap run and
///     is what all the AX window scanning needs.
///   - Input Monitoring (`IOHIDCheckAccess` for listen events) — governs
///     observing keystrokes.
///
/// The app has always prompted for Accessibility (via `Paster`); Input
/// Monitoring was never surfaced, so a machine with Accessibility granted but
/// Input Monitoring not-yet-decided can silently fail to receive keys.
@MainActor
enum KeyTapAccess {
    enum Status: Equatable {
        case granted
        case denied
        case undetermined

        var isGranted: Bool { self == .granted }

        /// A short label for the diagnostics readout.
        var label: String {
            switch self {
            case .granted: return "Granted"
            case .denied: return "Denied"
            case .undetermined: return "Not yet requested"
            }
        }
    }

    static var accessibility: Status {
        AXIsProcessTrusted() ? .granted : .denied
    }

    static var inputMonitoring: Status {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .undetermined
        }
    }

    /// Ask macOS to show the Input Monitoring prompt. Only actually prompts when
    /// the status is undetermined; once denied it silently no-ops (the user has
    /// to flip it in Settings), so callers pair this with `openInputMonitoringSettings`.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        log.info("requesting Input Monitoring access")
        return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openInputMonitoringSettings() {
        let anchor = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        if let url = URL(string: anchor) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Gate a key-tap mode on both permissions it needs, prompting for whichever
    /// is missing and returning false so the caller aborts — the user grants and
    /// re-triggers the hotkey. Mirrors the existing Accessibility-prompt flow, now
    /// covering Input Monitoring too (previously never requested, so keys could
    /// silently never arrive).
    static func ensureGranted() -> Bool {
        guard accessibility.isGranted else {
            log.info("key tap needs Accessibility; prompting")
            Paster.requestAccess()
            return false
        }
        switch inputMonitoring {
        case .granted:
            return true
        case .undetermined:
            // First encounter: this call shows the system Input Monitoring prompt.
            log.info("key tap needs Input Monitoring; prompting")
            requestInputMonitoring()
            NSSound.beep()
            return false
        case .denied:
            // Already refused — IOHIDRequestAccess won't re-prompt, so send them
            // to the settings pane instead.
            log.error("key tap blocked: Input Monitoring denied")
            openInputMonitoringSettings()
            NSSound.beep()
            return false
        }
    }

    /// Log both permission states — called once at launch so a support log shows
    /// whether a "keys don't work" report is really a permissions problem.
    static func logStatus() {
        let accessibilityLabel = accessibility.label
        let inputMonitoringLabel = inputMonitoring.label
        log.info("""
            permissions — Accessibility: \(accessibilityLabel, privacy: .public), \
            Input Monitoring: \(inputMonitoringLabel, privacy: .public)
            """)
    }
}
