import SwiftUI
import AppKit

@main
struct ClipborgApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The UI lives in a centered floating panel driven by the AppDelegate,
        // so this scene is intentionally empty.
        Settings { EmptyView() }
    }
}

/// Owns the long-lived history + watcher, the menu-bar status item, and the
/// centered floating panel. Hides the app from the Dock.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let history = ClipboardHistory()
    private var watcher: ClipboardWatcher?
    private var statusItem: NSStatusItem?
    private var panelController: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon, no app-switcher entry.
        NSApp.setActivationPolicy(.accessory)

        let watcher = ClipboardWatcher { [history] text, sourceApp in
            history.add(text, sourceApp: sourceApp)
        }
        watcher.start()
        self.watcher = watcher

        panelController = PanelController(history: history)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Clipborg"
        )
        item.button?.target = self
        item.button?.action = #selector(toggle)
        statusItem = item
    }

    @objc private func toggle() {
        panelController?.toggle()
    }
}
