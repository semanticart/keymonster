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
    private let viewModel: HistoryViewModel
    private var keyMonitor: Any?

    /// The app that was frontmost when the panel opened, so auto-paste can return
    /// focus to it. Captured before we activate ourselves.
    private var previousApp: NSRunningApplication?
    /// Avoids re-prompting for Accessibility on every untrusted paste in a session.
    private var didRequestAccess = false

    init(history: ClipboardHistory) {
        panel = FloatingPanel()
        viewModel = HistoryViewModel(history: history)

        let root = MenuContent(history: history, model: viewModel) { [weak panel] in
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
        viewModel.prepareForPresentation()
        previousApp = NSWorkspace.shared.frontmostApplication
        centerOnActiveScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Keep `self is nil` distinct from `handle returned nil`: optional
            // chaining would flatten both to nil, and `?? event` would then leak
            // every swallowed key (e.g. Ctrl-J) back into the search field.
            guard let self else { return event }
            return self.handle(event)
        }
    }

    /// Intercepts panel-level keys. Returns `nil` to swallow the event, or the
    /// event to let it through (e.g. typing into the search field).
    private func handle(_ event: NSEvent) -> NSEvent? {
        let hasControl = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.control)

        switch event.keyCode {
        case 53: // Escape
            hide()
            return nil
        case 45 where hasControl, 125: // Ctrl-N / Down — older
            viewModel.moveSelection(by: 1)
            return nil
        case 35 where hasControl, 126: // Ctrl-P / Up — newer
            viewModel.moveSelection(by: -1)
            return nil
        case 38 where hasControl: // Ctrl-J — scroll detail down
            viewModel.scrollDetail(by: viewModel.detailScrollStep)
            return nil
        case 40 where hasControl: // Ctrl-K — scroll detail up
            viewModel.scrollDetail(by: -viewModel.detailScrollStep)
            return nil
        case 36, 76: // Return / keypad Enter — copy, then paste into the prior app
            if viewModel.activateSelection() {
                let target = previousApp
                hide()
                pasteIfEnabled(into: target)
            }
            return nil
        default:
            return event
        }
    }

    /// After the selection is on the pasteboard, paste it into the prior app if
    /// auto-paste is on. If access is missing, prompt once and leave it copied.
    private func pasteIfEnabled(into target: NSRunningApplication?) {
        guard AppSettings.shared.autoPaste else { return }
        if Paster.isTrusted {
            Paster.paste(into: target)
        } else if !didRequestAccess {
            didRequestAccess = true
            log.info("auto-paste on but Accessibility not granted; prompting")
            Paster.requestAccess()
        }
    }

    private func hide() {
        log.debug("hide panel")
        panel.orderOut(nil)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
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
            contentRect: NSRect(x: 0, y: 0, width: 620 * uiScale, height: 500 * uiScale),
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
