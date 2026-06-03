import Combine
import SwiftUI
import AppKit
import SwiftData
import os.log

private let log = Logger(subsystem: "clipborg", category: "app")

@main
struct ClipborgApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // SwiftUI registers this as Cmd+, and puts "Settings…" in the app menu.
        Settings { SettingsView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let history = ClipboardHistory()
    private var watcher: ClipboardWatcher?
    private var statusItem: NSStatusItem?
    private var panelController: PanelController?
    private let hotkeyManager = HotkeyManager()
    private var cancellables: Set<AnyCancellable> = []
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)

        // SwiftData traps internally (EXC_BREAKPOINT) on any save when the
        // process has no bundle identifier — as is the case for a bare
        // `swift run` executable. Only enable persistence when running from a
        // real .app bundle (see `make run`). Without it the app still works,
        // keeping history in memory for the session; it just isn't saved.
        if Bundle.main.bundleIdentifier == nil {
            log.error("No bundle identifier — history will not persist this session.")
            log.error("Run via `make run` (a .app bundle), not `swift run`.")
        } else {
            do {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let storeDir = appSupport.appendingPathComponent("clipborg")
                try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
                let storeURL = storeDir.appendingPathComponent("history.store")
                let schema = Schema([PersistedClipItem.self])
                let config = ModelConfiguration(schema: schema, url: storeURL)
                let container = try ModelContainer(for: schema, configurations: config)
                history.configure(modelContext: container.mainContext)
            } catch {
                log.error("SwiftData setup failed: \(error)")
            }
        }

        let watcher = ClipboardWatcher { [history] content, sourceApp in
            history.add(content, sourceApp: sourceApp)
        }
        watcher.start()
        self.watcher = watcher

        panelController = PanelController(history: history)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Clipborg"
        )
        item.menu = buildStatusMenu()
        statusItem = item

        AppSettings.shared.$shortcut
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shortcut in
                self?.applyShortcut(shortcut)
            }
            .store(in: &cancellables)
    }

    // MARK: - Status item

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show History", action: #selector(toggleHistory), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Clipborg", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    @objc private func toggleHistory() {
        log.debug("toggleHistory")
        panelController?.toggle()
    }

    @objc func showSettings() {
        log.info("showSettings")
        if let win = settingsWindow, win.isVisible {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let win = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        win.title = "Clipborg Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 400, height: 160))
        win.center()
        settingsWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Hotkey

    private func applyShortcut(_ shortcut: Shortcut?) {
        if let hotkey = shortcut {
            log.info("registering hotkey keyCode=\(hotkey.keyCode) mods=\(hotkey.carbonModifiers)")
            hotkeyManager.register(hotkey) { [weak self] in self?.panelController?.toggle() }
        } else {
            log.info("clearing hotkey")
            hotkeyManager.unregister()
        }
    }
}
