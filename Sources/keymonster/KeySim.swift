#if DEBUG
import AppKit
import CoreGraphics

/// `keymonster keysim <step>...` — posts real keyboard events from a process
/// that holds the app's Accessibility grant, so hint/scroll modes can be
/// driven end-to-end without a human at the keyboard (osascript from a
/// terminal usually isn't trusted to send keystrokes). Debug-only tooling.
///
/// Steps, executed in order:
///   activate:<bundle-id-substring>   foreground a running app
///   delay:<seconds>                  sleep
///   key:<keyCode>[:<mod,mod...>]     press+release; mods: cmd,shift,opt,ctrl
///
/// Launch via `open -n --args …` like the other debug runners, so the posted
/// events come from the app's own TCC identity.
@MainActor
enum KeySimRunner {
    static func main() {
        guard let flagIndex = CommandLine.arguments.firstIndex(of: "keysim"),
              CommandLine.arguments.count > flagIndex + 1 else {
            fputs("usage: keymonster keysim <step>...\n", stderr)
            exit(2)
        }
        for step in CommandLine.arguments[(flagIndex + 1)...] {
            run(step: step)
        }
        exit(0)
    }

    private static func run(step: String) {
        let parts = step.split(separator: ":").map(String.init)
        switch parts.first {
        case "activate":
            let query = parts[1].lowercased()
            NSWorkspace.shared.runningApplications.first {
                $0.bundleIdentifier?.lowercased().contains(query) == true
            }?.activate()
        case "delay":
            usleep(UInt32((Double(parts[1]) ?? 1) * 1_000_000))
        case "key":
            let keyCode = CGKeyCode(Int(parts[1]) ?? 0)
            let flags = parts.count > 2 ? flags(from: parts[2]) : []
            for down in [true, false] {
                guard let event = CGEvent(
                    keyboardEventSource: nil, virtualKey: keyCode, keyDown: down
                ) else { continue }
                event.flags = flags
                event.post(tap: .cghidEventTap)
                usleep(30_000)
            }
        default:
            fputs("keysim: unknown step \(step)\n", stderr)
        }
    }

    private static func flags(from mods: String) -> CGEventFlags {
        var flags = CGEventFlags()
        for mod in mods.split(separator: ",") {
            switch mod {
            case "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt": flags.insert(.maskAlternate)
            case "ctrl": flags.insert(.maskControl)
            default: break
            }
        }
        return flags
    }
}
#endif
