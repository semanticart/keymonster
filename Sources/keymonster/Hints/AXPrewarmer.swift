import AppKit
import ApplicationServices
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints.prewarmer")

/// Keeps web apps' accessibility trees ready ahead of hint mode.
///
/// Chromium/Electron build their web-content AX tree lazily, ~2 seconds after an
/// assistive client first asks — so a hint mode triggered right after switching
/// to Slack or Chrome can catch only the native chrome. Setting the enable
/// attributes is what starts that build (the set "fails" with an error but still
/// triggers it). Doing so the moment you switch to a web app hides the latency:
/// by the time you reach for the hotkey, the content tree is already built.
@MainActor
final class AXPrewarmer {
    func start() {
        // No activation notification fires for whatever is already frontmost at
        // launch, so warm it directly, then every app switched to afterward.
        if let app = NSWorkspace.shared.frontmostApplication {
            enableAccessibility(for: app)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        enableAccessibility(for: app)
    }

    private func enableAccessibility(for app: NSRunningApplication) {
        guard WebApp.isWebBacked(app) else { return }
        log.debug("pre-warming \(app.bundleIdentifier ?? "?", privacy: .public)")
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}
