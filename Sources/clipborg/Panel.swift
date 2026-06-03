import SwiftUI
import AppKit
import os.log

private let log = Logger(subsystem: "clipborg", category: "panel")

/// Hosts `MenuContent` in a borderless, floating panel that appears centered on
/// the active screen. Toggled from the menu-bar status item; dismissed on Escape
/// or when the user clicks away.
@MainActor
final class PanelController {
    private let panel: FloatingPanel
    private var escMonitor: Any?

    init(history: ClipboardHistory) {
        panel = FloatingPanel()

        let root = MenuContent(history: history) { [weak panel] in
            panel?.orderOut(nil)
        }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        // Dismiss when focus leaves the panel (e.g. the user clicks elsewhere).
        NotificationCenter.default.addObserver(
            self, selector: #selector(resignedKey),
            name: NSWindow.didResignKeyNotification, object: panel
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    private func show() {
        log.debug("show panel")
        centerOnActiveScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func hide() {
        log.debug("hide panel")
        panel.orderOut(nil)
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
    }

    @objc private func resignedKey() {
        hide()
    }

    private func centerOnActiveScreen() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}

/// A borderless, non-activating panel with a transparent background so the
/// SwiftUI content's rounded material shows through with a drop shadow.
final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420 * uiScale, height: 540 * uiScale),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
    }

    // Borderless panels can't become key unless we opt in; needed for buttons
    // and the Escape monitor to work.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
