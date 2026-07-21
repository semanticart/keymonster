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
    private let gridMode = GridModeController()
    private let textJumpMode = TextJumpController()
    private let menuFinder = MenuFinderController()
    private let scriptRunner = ScriptRunner()
    private var cancellables: Set<AnyCancellable> = []
    private var settingsWindow: NSWindow?
    private var settingsSizeObservation: NSKeyValueObservation?

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

        // Re-register the full hotkey set on any settings change. objectWillChange
        // fires before the new value lands, so we hop to the next runloop turn
        // (receive(on:)) to read the settled values; re-registering wholesale on
        // every change is harmless since HotkeyManager.register replaces the set.
        AppSettings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyHotkeys()
            }
            .store(in: &cancellables)
        applyHotkeys()

        if !AppSettings.shared.hasLaunched {
            AppSettings.shared.hasLaunched = true
            log.info("first run: showing settings")
            showSettings()
        }
    }

    // MARK: - Status item

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let showItem = NSMenuItem(title: "Show Clipboard History", action: #selector(toggleHistory), keyEquivalent: "")
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
        // As an accessory app we're not activated by the status-item click, so
        // an already-open window that another app covers won't come forward
        // from makeKeyAndOrderFront alone — activate first.
        if let win = settingsWindow, win.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        // Track the SwiftUI content's ideal size in preferredContentSize so the
        // window can auto-size to whichever tab is selected (tabs have no
        // scrolling, so each one's ideal height is its full content).
        hosting.sizingOptions = .preferredContentSize
        hosting.view.layoutSubtreeIfNeeded()
        let win = NSWindow(contentViewController: hosting)
        win.title = "Key Monster Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(hosting.view.fittingSize)
        win.center()
        settingsSizeObservation = hosting.observe(\.preferredContentSize, options: [.new]) { [weak win] _, change in
            guard let size = change.newValue, size != .zero else { return }
            // KVO fires on the main thread here (the size changes during AppKit
            // layout), so assuming isolation is safe.
            MainActor.assumeIsolated {
                win?.resizeContentKeepingTopLeft(to: size)
            }
        }
        settingsWindow = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Hotkey

    private func applyHotkeys() {
        // While a shortcut is being recorded, register nothing: a combo that's
        // mid-capture shouldn't also fire as a live global hotkey. This re-runs
        // (via the objectWillChange subscription above) once recording ends.
        guard !AppSettings.shared.suspendHotkeys else {
            log.info("hotkeys suspended while recording")
            hotkeyManager.register([])
            return
        }

        // Order matters: when two entries share a shortcut, only the first one
        // registered actually fires (see ShortcutConflicts), so this must match
        // the order the settings UI lists them in (and previously registered them in).
        let settings = AppSettings.shared
        var entries: [(shortcut: Shortcut?, action: () -> Void)] = [
            (settings.shortcut, { [weak self] in self?.panelController?.toggle() })
        ]
        for entry in settings.appShortcuts {
            guard !entry.apps.isEmpty else { continue }
            let apps = entry.apps
            entries.append((entry.shortcut, { [weak self] in self?.appFocuser.focus(apps) }))
        }
        entries.append(contentsOf: [
            (settings.hintLeftShortcut, { [weak self] in self?.hintMode.toggle(button: .left) }),
            (settings.hintRightShortcut, { [weak self] in self?.hintMode.toggle(button: .right) }),
            (settings.gridShortcut, { [weak self] in self?.gridMode.toggle() }),
            (settings.textJumpShortcut, { [weak self] in self?.textJumpMode.toggle() }),
            (settings.menuSearchShortcut, { [weak self] in self?.menuFinder.toggle() })
        ])
        for script in settings.scriptShortcuts {
            guard !script.isEmpty else { continue }
            entries.append((script.shortcut, { [scriptRunner] in scriptRunner.run(script) }))
        }

        let bindings = entries.compactMap { entry -> HotkeyBinding? in
            guard let shortcut = entry.shortcut else { return nil }
            return HotkeyBinding(shortcut: shortcut, action: entry.action)
        }

        log.info("registering \(bindings.count) hotkey(s)")
        hotkeyManager.register(bindings)
    }
}

private extension NSWindow {
    /// Resize to a new content size, keeping the top-left corner where it is —
    /// how Settings-style windows grow and shrink when tabs change. A plain
    /// setContentSize pins the bottom-left instead, so the title bar would jump.
    func resizeContentKeepingTopLeft(to contentSize: NSSize) {
        var frame = frame
        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        frame.size = frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
        guard frame != self.frame else { return }
        setFrame(frame, display: true, animate: true)
    }
}
