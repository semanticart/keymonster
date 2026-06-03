import AppKit
import Foundation

struct Shortcut: Codable, Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    var displayString: String {
        ShortcutFormatter.format(keyCode: Int(keyCode), carbonModifiers: Int(carbonModifiers))
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let shortcutKey = "globalShortcut"

    private let defaults: UserDefaults

    @Published var shortcut: Shortcut? {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.shortcutKey),
           let decoded = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = decoded
        }
    }

    private func persist() {
        if let value = shortcut, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: Self.shortcutKey)
        } else {
            defaults.removeObject(forKey: Self.shortcutKey)
        }
    }
}

enum ShortcutFormatter {
    static func format(keyCode: Int, carbonModifiers: Int) -> String {
        // Carbon modifier constants
        let cmdKey    = 0x0100
        let shiftKey  = 0x0200
        let optionKey = 0x0800
        let controlKey = 0x1000

        var result = ""
        if carbonModifiers & controlKey != 0 { result += "⌃" }
        if carbonModifiers & optionKey != 0 { result += "⌥" }
        if carbonModifiers & shiftKey != 0 { result += "⇧" }
        if carbonModifiers & cmdKey != 0 { result += "⌘" }
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
    if flags.contains(.command) { mods |= 0x0100 }
    if flags.contains(.shift) { mods |= 0x0200 }
    if flags.contains(.option) { mods |= 0x0800 }
    if flags.contains(.control) { mods |= 0x1000 }
    return mods
}
