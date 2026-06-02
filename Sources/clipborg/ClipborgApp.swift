import SwiftUI
import AppKit

@main
struct ClipborgApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Clipborg", systemImage: "doc.on.clipboard") {
            MenuContent(history: delegate.history)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the long-lived history + watcher and hides the app from the Dock.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let history = ClipboardHistory()
    private var watcher: ClipboardWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon, no app-switcher entry.
        NSApp.setActivationPolicy(.accessory)

        let history = history
        let watcher = ClipboardWatcher { text in
            history.add(text)
        }
        watcher.start()
        self.watcher = watcher
    }
}
