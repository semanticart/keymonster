import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints.keypanel")

/// The experimental focus-based key-capture backend: instead of tapping events,
/// an invisible non-activating panel takes key-window status (the same
/// mechanism as the clipboard `FloatingPanel`), so mode keystrokes arrive
/// through the ordinary responder chain.
///
/// Why bother: Secure Keyboard Entry only starves *eavesdroppers* — the key
/// window still receives its keystrokes — so this path keeps working while a
/// stuck password manager holds secure input, and it needs no Input Monitoring
/// permission. The trade-offs against the tap: the target app loses keyboard
/// focus while a mode is active (it regains it when the panel closes), and a
/// non-hint keystroke (a ⌘-chord, a stray Return) is consumed along with the
/// dismissal instead of passing through to the app.
@MainActor
final class HintKeyPanel {
    var handler: ((HintKeyEvent) -> Void)?
    /// The keystroke rules for the active mode; see `HintKeyClassifier`.
    var classifier = HintKeyClassifier()

    private var panel: KeyCapturePanel?
    private var mouseMonitors: [Any] = []

    /// Puts up the capture panel and takes key focus. Mirrors
    /// `HintKeyTap.start`'s contract; this backend has no permission to lack,
    /// so it only fails if AppKit refuses key status outright.
    func start() -> Bool {
        guard panel == nil else { return true }
        let panel = KeyCapturePanel()
        panel.onKey = { [weak self] event in self?.handleKey(event) }
        panel.onResign = { [weak self] in
            // Focus went elsewhere (another app activated, a system overlay) —
            // the mode can no longer see keys, so treat it as a dismissal.
            self?.handler?(.cancel)
        }
        panel.makeKeyAndOrderFront(nil)
        guard panel.isKeyWindow else {
            log.error("capture panel failed to become key")
            panel.onResign = nil
            panel.orderOut(nil)
            return false
        }
        self.panel = panel

        // The tap cancels on real clicks; monitors reproduce that. Global for
        // clicks landing in other apps, local for clicks on our own windows.
        // (Synthesized commit clicks can't trip these: modes stop() before
        // clicking.)
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.handler?(.cancel) }
            }
        ) {
            mouseMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.handler?(.cancel) }
                return event
            }
        ) {
            mouseMonitors.append(monitor)
        }
        log.debug("focus capture panel active")
        return true
    }

    func stop() {
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
        mouseMonitors = []
        guard let panel else { return }
        // Detach callbacks before orderOut: tearing down makes the panel
        // resign key, which must not re-enter the mode's dismiss.
        panel.onKey = nil
        panel.onResign = nil
        panel.orderOut(nil)
        self.panel = nil
    }

    private func handleKey(_ event: NSEvent) {
        if let key = classifier.classify(event) {
            log.debug("keyDown \(event.keyCode): captured as hint input")
            handler?(key)
        } else {
            // Not hint input (a chord, Tab, …). Unlike the tap, the keystroke
            // was already delivered to us and is consumed; just dismiss.
            log.debug("keyDown \(event.keyCode): not hint input, cancelling")
            handler?(.cancel)
        }
    }
}

/// A 1×1 transparent panel whose only job is to be the key window and forward
/// `keyDown`. Non-activating, so the frontmost app stays active (menu bar and
/// window chrome unchanged) and regains keyboard focus the moment the panel
/// orders out — the same trick the clipboard panel uses.
private final class KeyCapturePanel: NSPanel {
    var onKey: ((NSEvent) -> Void)?
    var onResign: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
    }

    // Borderless panels can't become key unless we opt in — being key is this
    // window's entire purpose.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        // No super: the default implementation beeps for unhandled keys.
        onKey?(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘-chords arrive here rather than keyDown. Report them (they classify
        // to `.cancel`) and claim them so they don't fall through to our app's
        // own key equivalents.
        onKey?(event)
        return true
    }

    override func resignKey() {
        super.resignKey()
        onResign?()
    }
}
