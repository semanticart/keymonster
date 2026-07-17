import SwiftUI
import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "menufinder")

/// A menu-finder key mapped to a panel action, or nil to let the keystroke reach
/// the search field. Pure and testable, mirroring `PanelCommand`; there's no
/// detail pane here, so the set is smaller.
enum MenuFinderCommand: Equatable {
    case dismiss
    /// Move the highlight by this many rows (positive = down).
    case moveSelection(Int)
    /// Run the highlighted menu item.
    case activate

    static func from(keyCode: UInt16, control: Bool) -> MenuFinderCommand? {
        switch keyCode {
        case 53: // Escape
            return .dismiss
        case 45 where control, 125: // Ctrl-N / Down
            return .moveSelection(1)
        case 35 where control, 126: // Ctrl-P / Up
            return .moveSelection(-1)
        case 36, 76: // Return / keypad Enter
            return .activate
        default:
            return nil
        }
    }
}

/// Hosts `MenuFinderContent` in a floating, centered panel that lists the
/// frontmost app's menu items for fuzzy search. Triggered by a global shortcut;
/// Return presses the highlighted item back in that app.
@MainActor
final class MenuFinderController {
    private let panel: FloatingPanel
    private let viewModel = MenuFinderViewModel()
    private var keyMonitor: Any?

    /// The app that was frontmost when the panel opened — the one whose menus we
    /// scanned and the one we press the item back into. Captured before we
    /// activate ourselves and steal focus.
    private var previousApp: NSRunningApplication?
    /// Pressable AX element for each scanned item, keyed by `MenuBarItem.id`.
    private var elements: [Int: AXUIElement] = [:]
    /// Avoids re-prompting for Accessibility on every press in a session.
    private var didRequestAccess = false

    private static let panelSize = NSSize(width: 540 * uiScale, height: 460 * uiScale)

    init() {
        panel = FloatingPanel(contentSize: Self.panelSize)

        let root = MenuFinderContent(model: viewModel) { [weak self] in self?.hide() }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

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
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        // Reading another app's menus needs Accessibility access. Without it the
        // scan comes back empty, so prompt once and don't bother showing the panel.
        guard Paster.isTrusted else {
            log.info("menu finder needs Accessibility; prompting")
            if !didRequestAccess {
                didRequestAccess = true
                Paster.requestAccess()
            }
            return
        }

        log.debug("show menu finder for \(app.bundleIdentifier ?? "?")")
        previousApp = app
        let scan = AXMenuBarScanner.scan(app: app)
        elements = scan?.elements ?? [:]
        viewModel.present(items: scan?.items ?? [], appName: scan?.appName ?? app.localizedName ?? "")

        centerOnActiveScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    /// Intercepts panel-level keys. Returns `nil` to swallow the event, or the
    /// event to let it fall through to the search field.
    private func handle(_ event: NSEvent) -> NSEvent? {
        let hasControl = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.control)
        guard let command = MenuFinderCommand.from(keyCode: event.keyCode, control: hasControl) else {
            return event
        }

        switch command {
        case .dismiss:
            hide()
        case .moveSelection(let delta):
            viewModel.moveSelection(by: delta)
        case .activate:
            if let item = viewModel.activateSelection(), let element = elements[item.id] {
                let target = previousApp
                hide()
                press(element, into: target)
            }
        }
        return nil
    }

    /// Return focus to the app the menu belongs to, then press the item — some
    /// menu actions operate on that app's key window, so it must be frontmost.
    private func press(_ element: AXUIElement, into app: NSRunningApplication?) {
        app?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AXMenuBarScanner.press(element)
        }
    }

    private func hide() {
        log.debug("hide menu finder")
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
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
    }
}
