import Combine
import SwiftUI
import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "app")

/// Process entry point. Normally launches the full menu-bar app; with a
/// `snapshot` argument it renders the history panel headlessly instead (see
/// `SnapshotRunner`) so the design can be iterated on autonomously.
@main
enum Entry {
    static func main() {
        if CommandLine.arguments.dropFirst().contains("snapshot") {
            MainActor.assumeIsolated { SnapshotRunner.main() }
        } else {
            KeyMonsterApp.main()
        }
    }
}

struct KeyMonsterApp: App {
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
    private let appFocuser = AppFocuser()
    private let hintMode = HintModeController()
    private var cancellables: Set<AnyCancellable> = []
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)

        do {
            let store = try SQLiteClipStore(url: SQLiteClipStore.defaultURL())
            history.configure(store: store)
        } catch {
            log.error("SQLite setup failed: \(error)")
        }

        let watcher = ClipboardWatcher { [history] content, sourceApp, richData, richType in
            history.add(content, sourceApp: sourceApp, richTextData: richData, richTextType: richType)
        }
        watcher.start()
        self.watcher = watcher

        panelController = PanelController(history: history)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = MenuBarIcon.image()
        icon.accessibilityDescription = "Key Monster"
        item.button?.image = icon
        item.menu = buildStatusMenu()
        statusItem = item

        // Re-register the full hotkey set whenever the history shortcut, any of
        // the app-focus shortcuts, or the hint shortcuts change. combineLatest
        // emits the current values immediately, so this also performs the
        // initial registration.
        AppSettings.shared.$shortcut
            .combineLatest(
                AppSettings.shared.$appShortcuts,
                AppSettings.shared.$hintLeftShortcut,
                AppSettings.shared.$hintRightShortcut
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyHotkeys()
            }
            .store(in: &cancellables)

        if !AppSettings.shared.hasLaunched {
            AppSettings.shared.hasLaunched = true
            log.info("first run: showing settings")
            showSettings()
        }
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
        let quitItem = NSMenuItem(title: "Quit Key Monster", action: #selector(quit), keyEquivalent: "")
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
        let hosting = NSHostingController(rootView: SettingsView())
        hosting.view.layoutSubtreeIfNeeded()
        let win = NSWindow(contentViewController: hosting)
        win.title = "Key Monster Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(hosting.view.fittingSize)
        win.center()
        settingsWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Hotkey

    private func applyHotkeys() {
        var bindings: [HotkeyBinding] = []

        if let historyShortcut = AppSettings.shared.shortcut {
            bindings.append(HotkeyBinding(shortcut: historyShortcut) { [weak self] in
                self?.panelController?.toggle()
            })
        }

        for entry in AppSettings.shared.appShortcuts {
            guard let shortcut = entry.shortcut, !entry.apps.isEmpty else { continue }
            let apps = entry.apps
            bindings.append(HotkeyBinding(shortcut: shortcut) { [weak self] in
                self?.appFocuser.focus(apps)
            })
        }

        if let hintLeft = AppSettings.shared.hintLeftShortcut {
            bindings.append(HotkeyBinding(shortcut: hintLeft) { [weak self] in
                self?.hintMode.toggle(button: .left)
            })
        }
        if let hintRight = AppSettings.shared.hintRightShortcut {
            bindings.append(HotkeyBinding(shortcut: hintRight) { [weak self] in
                self?.hintMode.toggle(button: .right)
            })
        }

        log.info("registering \(bindings.count) hotkey(s)")
        hotkeyManager.register(bindings)
    }
}
