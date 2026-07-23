import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints")

/// Screenshots the screen region a zoomed hint view magnifies.
enum WindowCapture {
    /// Whether we've already raised the system Screen Recording prompt this
    /// launch, and whether we've already offered the System Settings pane after
    /// the prompt was declined. One shot each, so a permission-less session
    /// degrades to sketched outlines instead of nagging on every zoom.
    @MainActor private static var didPrompt = false
    @MainActor private static var didOfferSettings = false

    /// An image of `bounds` (global display coordinates, top-left origin — the
    /// same space AX frames are in) showing what's beneath `window`, so the
    /// overlay's own badges never appear in the shot. Without Screen Recording
    /// permission this raises the system prompt and returns nil; the zoom view
    /// sketches the member outlines until the grant takes effect (macOS applies
    /// it on relaunch).
    @MainActor
    static func below(_ window: NSWindow?, bounds: CGRect) -> CGImage? {
        if !CGPreflightScreenCaptureAccess() {
            guard requestAccess() else { return nil }
        }
        guard let window, window.windowNumber > 0 else { return nil }
        return CGWindowListCreateImage(
            bounds, .optionOnScreenBelowWindow, CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        )
    }

    /// Raise the system Screen Recording prompt, working around its prompt-once
    /// behavior: TCC suppresses the dialog forever once a denied (or stale, e.g.
    /// after a re-sign) row exists, so first clear our row — safe, since
    /// preflight just said it grants nothing — and then request. If the user
    /// declined that prompt earlier this launch, offer the Settings pane once
    /// instead. Returns whether capture can proceed right now.
    @MainActor
    private static func requestAccess() -> Bool {
        if !didPrompt {
            didPrompt = true
            log.info("no Screen Recording permission; resetting TCC row and prompting")
            resetTCCRow()
            return CGRequestScreenCaptureAccess()
        }
        if !didOfferSettings {
            didOfferSettings = true
            // Deferred: below(_:bounds:) runs mid-layout of the zoom overlay,
            // and runModal would re-enter that.
            DispatchQueue.main.async { offerSettings() }
        }
        return false
    }

    /// Delete our Screen Recording row from the TCC database so the system
    /// prompt can appear again. Runs the user-level `tccutil` (no sudo needed
    /// for this service); a dev build with no bundle identifier has no row to
    /// clear, so this is a no-op there.
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
            Until Screen Recording is granted (and Key Monster is relaunched), \
            zoom shows sketched outlines instead of real pixels.
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
