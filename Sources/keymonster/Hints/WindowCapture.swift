import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints")

/// Screenshots the screen region a zoomed hint view magnifies.
enum WindowCapture {
    /// Whether we've already raised the system Screen Recording prompt this
    /// launch. TCC shows it at most once, so later blocked attempts get our
    /// own alert offering the Settings pane instead.
    @MainActor private static var didPrompt = false

    /// Whether zoom can capture the screen right now. When it can't, raises
    /// the system Screen Recording prompt (first attempt this launch) or an
    /// alert offering the Settings pane, and returns false — callers should
    /// treat zoom as unavailable and dismiss rather than degrade.
    @MainActor
    static func ensureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if !didPrompt {
            didPrompt = true
            log.info("no Screen Recording permission; resetting TCC row and prompting")
            resetTCCRow()
            return CGRequestScreenCaptureAccess()
        }
        // Deferred: callers sit mid-keystroke handling, and runModal would
        // re-enter that.
        DispatchQueue.main.async { offerSettings() }
        return false
    }

    /// An image of `bounds` (global display coordinates, top-left origin — the
    /// same space AX frames are in) showing what's beneath `window`, so the
    /// overlay's own badges never appear in the shot. Gate with
    /// `ensureAccess()` first; without permission (or if capture fails) this
    /// returns nil.
    @MainActor
    static func below(_ window: NSWindow?, bounds: CGRect) -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard let window, window.windowNumber > 0 else { return nil }
        return CGWindowListCreateImage(
            bounds, .optionOnScreenBelowWindow, CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        )
    }

    /// Delete our Screen Recording row from the TCC database so the system
    /// prompt can appear again: TCC suppresses the dialog forever once a
    /// denied (or stale, e.g. after a re-sign) row exists — safe, since
    /// preflight just said it grants nothing. Runs the user-level `tccutil`
    /// (no sudo needed for this service); a dev build with no bundle
    /// identifier has no row to clear, so this is a no-op there.
    private static func resetTCCRow() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "ScreenCapture", bundleID]
        do {
            try reset.run()
            reset.waitUntilExit()
        } catch {
            log.error("tccutil reset failed: \(error)")
        }
    }

    @MainActor
    private static func offerSettings() {
        let alert = NSAlert()
        alert.messageText = "Zoom needs Screen Recording permission"
        alert.informativeText = """
            Key Monster magnifies a screenshot of the area you zoom into. \
            The shot lives only in memory and is discarded when the zoom \
            closes — nothing is saved, and no audio or video is ever recorded. \
            Zoom stays unavailable until Screen Recording is granted and \
            Key Monster is relaunched.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
    }
}
