import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "focuser")

/// Decides which app a focus shortcut should bring forward. Pure so the cycling
/// behaviour can be tested without touching the running app list.
enum AppFocus {
    /// Given the apps bound to a shortcut and the bundle id of the frontmost app,
    /// return the bundle id to activate. If one of the candidates is already
    /// frontmost, advance to the next (wrapping) so repeated presses cycle through
    /// the set; otherwise focus the first.
    static func nextTarget(candidates: [String], frontmost: String?) -> String? {
        guard !candidates.isEmpty else { return nil }
        if let frontmost, let index = candidates.firstIndex(of: frontmost) {
            return candidates[(index + 1) % candidates.count]
        }
        return candidates[0]
    }
}

@MainActor
struct AppFocuser {
    /// Frontmost app's bundle id. Injected so callers/tests can override it.
    var frontmostBundleID: () -> String? = {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func focus(_ apps: [AppRef]) {
        let bundleIDs = apps.map(\.bundleID)
        guard let target = AppFocus.nextTarget(candidates: bundleIDs, frontmost: frontmostBundleID()) else {
            return
        }
        activate(bundleID: target)
    }

    private func activate(bundleID: String) {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            log.debug("activating \(bundleID)")
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            log.debug("launching \(bundleID)")
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            log.error("no app found for bundle id \(bundleID)")
        }
    }
}
