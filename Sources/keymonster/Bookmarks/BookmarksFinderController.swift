import SwiftUI
import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "bookmarks")

/// A bookmarks-finder key mapped to a panel action, or nil to let the
/// keystroke reach the search field. Mirrors `MenuFinderCommand`.
enum BookmarksFinderCommand: Equatable {
    case dismiss
    /// Move the highlight by this many rows (positive = down).
    case moveSelection(Int)
    /// Open the highlighted bookmark.
    case activate

    static func from(keyCode: UInt16, control: Bool) -> BookmarksFinderCommand? {
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

/// Hosts `BookmarksFinderContent` in a floating, centered panel that lists
/// bookmarks loaded from the CSV file (see `BookmarksStore`) for fuzzy search
/// by title. Triggered by a global shortcut; Return opens the highlighted
/// bookmark's url in the default browser. Mirrors `MenuFinderController`, but
/// simpler — no accessibility scanning or pressing is involved.
@MainActor
final class BookmarksFinderController {
    private let panel: FloatingPanel
    private let viewModel = BookmarksFinderViewModel()
    private var keyMonitor: Any?

    private static let panelSize = NSSize(width: 540 * uiScale, height: 460 * uiScale)

    init() {
        panel = FloatingPanel(contentSize: Self.panelSize)

        let root = BookmarksFinderContent(model: viewModel) { [weak self] in self?.hide() }
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
        log.debug("show bookmarks finder")
        try? BookmarksStore.ensureExists()
        viewModel.present(bookmarks: BookmarksStore.load())

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
        guard let command = BookmarksFinderCommand.from(keyCode: event.keyCode, control: hasControl) else {
            return event
        }

        switch command {
        case .dismiss:
            hide()
        case .moveSelection(let delta):
            viewModel.moveSelection(by: delta)
        case .activate:
            open(viewModel.activateSelection())
        }
        return nil
    }

    private func open(_ bookmark: Bookmark?) {
        guard let bookmark, let url = bookmark.resolvedURL else {
            NSSound.beep()
            return
        }
        hide()
        NSWorkspace.shared.open(url)
    }

    private func hide() {
        log.debug("hide bookmarks finder")
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
