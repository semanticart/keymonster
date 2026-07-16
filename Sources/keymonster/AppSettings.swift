import AppKit
import Foundation
import ServiceManagement

/// Carbon's modifier-flag bits, as used by RegisterEventHotKey and the Shortcut
/// encoding. Defined once here; ShortcutFormatter, carbonModifiers(from:), and
/// the tests all reference these instead of repeating the magic numbers.
enum CarbonModifierMask {
    static let command: UInt32 = 0x0100
    static let shift: UInt32 = 0x0200
    static let option: UInt32 = 0x0800
    static let control: UInt32 = 0x1000
}

struct Shortcut: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    var displayString: String {
        ShortcutFormatter.format(keyCode: Int(keyCode), carbonModifiers: Int(carbonModifiers))
    }
}

/// Finds key combos bound more than once. A shortcut can only be registered by a
/// single hotkey, so duplicates (across the history shortcut and every focus
/// shortcut) mean all but the first silently fail to register.
enum ShortcutConflicts {
    static func conflicting(_ shortcuts: [Shortcut]) -> Set<Shortcut> {
        var counts: [Shortcut: Int] = [:]
        for shortcut in shortcuts {
            counts[shortcut, default: 0] += 1
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }
}

/// A target application for a focus shortcut. We store the bundle identifier
/// (stable, used to activate/launch) plus a display name for the settings UI.
struct AppRef: Codable, Equatable, Hashable, Identifiable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}

/// Binds a global shortcut to one or more apps. Firing the shortcut focuses the
/// first app; pressing it again while one of them is frontmost cycles to the
/// next, so a single key can rotate through e.g. Slack and Chrome.
struct AppShortcut: Codable, Equatable, Identifiable {
    var id: UUID
    var shortcut: Shortcut?
    var apps: [AppRef]

    init(id: UUID = UUID(), shortcut: Shortcut? = nil, apps: [AppRef] = []) {
        self.id = id
        self.shortcut = shortcut
        self.apps = apps
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let shortcutKey = "globalShortcut"
    static let appShortcutsKey = "appFocusShortcuts"
    static let autoPasteKey = "autoPaste"
    static let hasLaunchedKey = "hasLaunched"
    static let hintLeftShortcutKey = "hintLeftClickShortcut"
    static let hintRightShortcutKey = "hintRightClickShortcut"
    static let gridShortcutKey = "gridClickShortcut"
    static let textJumpShortcutKey = "textJumpShortcut"

    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Revert to the actual state if the call failed.
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private let defaults: UserDefaults

    /// False until the app has launched once. Used to show Settings on first run
    /// so the user can pick a shortcut and grant Accessibility for auto-paste.
    var hasLaunched: Bool {
        get { defaults.bool(forKey: Self.hasLaunchedKey) }
        set { defaults.set(newValue, forKey: Self.hasLaunchedKey) }
    }

    @Published var shortcut: Shortcut? {
        didSet { persist(shortcut, forKey: Self.shortcutKey) }
    }

    /// Global shortcuts that focus (or cycle through) a set of apps.
    @Published var appShortcuts: [AppShortcut] {
        didSet { persistAppShortcuts() }
    }

    /// Global shortcut that overlays click hints on the frontmost window and
    /// left-clicks the chosen element.
    @Published var hintLeftShortcut: Shortcut? {
        didSet { persist(hintLeftShortcut, forKey: Self.hintLeftShortcutKey) }
    }

    /// Same as `hintLeftShortcut`, but the chosen element is right-clicked.
    @Published var hintRightShortcut: Shortcut? {
        didSet { persist(hintRightShortcut, forKey: Self.hintRightShortcutKey) }
    }

    /// Global shortcut that overlays a home-row grid on the frontmost window;
    /// each keypress zooms into a cell until Return (or an unsplittable cell)
    /// clicks its center.
    @Published var gridShortcut: Shortcut? {
        didSet { persist(gridShortcut, forKey: Self.gridShortcutKey) }
    }

    /// Global shortcut that, over the focused text field, labels every
    /// occurrence of the next character typed; picking a label places the caret
    /// just before that character.
    @Published var textJumpShortcut: Shortcut? {
        didSet { persist(textJumpShortcut, forKey: Self.textJumpShortcutKey) }
    }

    /// When on, pressing Return pastes the selection into the previously focused
    /// app instead of only copying it. Defaults on; requires Accessibility access.
    @Published var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: Self.autoPasteKey) }
    }

    /// True while ShortcutRecorder is capturing a key combo. Not persisted:
    /// AppDelegate registers no hotkeys while this is set, so a combo being
    /// recorded can't also trigger a live global shortcut.
    @Published var suspendHotkeys: Bool = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoPaste = defaults.object(forKey: Self.autoPasteKey) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        shortcut = Self.loadShortcut(defaults, key: Self.shortcutKey)
        hintLeftShortcut = Self.loadShortcut(defaults, key: Self.hintLeftShortcutKey)
        hintRightShortcut = Self.loadShortcut(defaults, key: Self.hintRightShortcutKey)
        gridShortcut = Self.loadShortcut(defaults, key: Self.gridShortcutKey)
        textJumpShortcut = Self.loadShortcut(defaults, key: Self.textJumpShortcutKey)
        if let data = defaults.data(forKey: Self.appShortcutsKey),
           let decoded = try? JSONDecoder().decode([AppShortcut].self, from: data) {
            appShortcuts = decoded
        } else {
            appShortcuts = []
        }
    }

    private static func loadShortcut(_ defaults: UserDefaults, key: String) -> Shortcut? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    private func persist(_ shortcut: Shortcut?, forKey key: String) {
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func persistAppShortcuts() {
        if appShortcuts.isEmpty {
            defaults.removeObject(forKey: Self.appShortcutsKey)
        } else if let data = try? JSONEncoder().encode(appShortcuts) {
            defaults.set(data, forKey: Self.appShortcutsKey)
        }
    }
}

enum ShortcutFormatter {
    static func format(keyCode: Int, carbonModifiers: Int) -> String {
        let mods = UInt32(carbonModifiers)
        var result = ""
        if mods & CarbonModifierMask.control != 0 { result += "⌃" }
        if mods & CarbonModifierMask.option != 0 { result += "⌥" }
        if mods & CarbonModifierMask.shift != 0 { result += "⇧" }
        if mods & CarbonModifierMask.command != 0 { result += "⌘" }
        result += keyCharacter(for: keyCode)
        return result
    }

    private static func keyCharacter(for keyCode: Int) -> String {
        let map: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
            32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'",
            40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
            48: "⇥", 49: "Space", 50: "`", 51: "⌫",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
            103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
            123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return map[keyCode] ?? "?"
    }
}

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var mods: UInt32 = 0
    if flags.contains(.command) { mods |= CarbonModifierMask.command }
    if flags.contains(.shift) { mods |= CarbonModifierMask.shift }
    if flags.contains(.option) { mods |= CarbonModifierMask.option }
    if flags.contains(.control) { mods |= CarbonModifierMask.control }
    return mods
}
