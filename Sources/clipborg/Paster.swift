import AppKit
import ApplicationServices
import CoreGraphics
import os.log

private let log = Logger(subsystem: "clipborg", category: "paster")

/// Pastes the just-copied selection into whichever app was frontmost before the
/// panel appeared, by reactivating that app and synthesizing a ⌘V keystroke.
///
/// This needs Accessibility permission (to post key events into another app). We
/// never depend on it: callers copy to the pasteboard first, so if permission is
/// missing the user can still paste manually — auto-paste is a pure enhancement.
enum Paster {
    /// Whether the app currently has Accessibility access. Cheap, no prompt.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Ask for Accessibility access. If not already granted this opens the
    /// System Settings pane; the grant only takes effect after a relaunch, so the
    /// triggering paste won't succeed. Safe to call repeatedly. Returns current trust.
    @discardableResult
    static func requestAccess() -> Bool {
        // The literal value of kAXTrustedCheckOptionPrompt; using the imported
        // global trips Swift 6's shared-mutable-state check.
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Reveal the Accessibility list in System Settings so the user can grant access.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Reactivate `app` and send ⌘V into it. No-op (returns false) if untrusted or
    /// there's no target app; the content is assumed already on the pasteboard.
    @discardableResult
    static func paste(into app: NSRunningApplication?) -> Bool {
        guard isTrusted else { log.debug("paste skipped: not trusted"); return false }
        guard let app, app != .current else { log.debug("paste skipped: no target app"); return false }

        log.debug("pasting into \(app.localizedName ?? "?")")
        app.activate()
        // Let the target app become frontmost before the keystroke lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            postCommandV()
        }
        return true
    }

    private static func postCommandV() {
        let vKeyCode: CGKeyCode = 0x09 // 'v'
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
