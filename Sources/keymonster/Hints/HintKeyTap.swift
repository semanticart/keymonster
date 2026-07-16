import AppKit
import CoreGraphics

/// Smuggles a non-Sendable value across an isolation boundary that is known to
/// stay on one thread (the tap callback and its handling both run on main).
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

/// One keystroke's meaning while hint mode is showing.
enum HintKeyEvent: Equatable {
    case letter(Character, shifted: Bool)
    case escape
    case backspace
    /// Anything else — a chorded shortcut, a mouse click, cmd-tab. Hint mode
    /// should get out of the way and let the event through.
    case cancel
}

/// Grabs keystrokes before they reach the frontmost app via a CGEvent tap while
/// hint mode is active (Accessibility permission, which hint mode needs anyway,
/// also authorizes the tap). Plain letters, Escape, and Delete are swallowed and
/// forwarded to `handler`; everything else passes through untouched but reports
/// `.cancel` so hint mode can dismiss itself.
@MainActor
final class HintKeyTap {
    var handler: ((HintKeyEvent) -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// Returns false when the tap can't be created (Accessibility revoked).
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        // C callback: no captures allowed, so `self` travels through userInfo.
        // The runloop source lives on the main runloop, so the callback always
        // runs on the main thread — the box only exists to carry the non-Sendable
        // CGEvent across `assumeIsolated`'s Sendable requirement.
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let keyTap = Unmanaged<HintKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
            let box = UncheckedSendableBox(value: event)
            let swallow = MainActor.assumeIsolated {
                keyTap.process(type: type, event: box.value)
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        source = nil
        tap = nil
    }

    /// Returns whether the event should be swallowed (not delivered to the app).
    private func process(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system disables taps that stall; re-arm and carry on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown, .rightMouseDown:
            handler?(.cancel)
            return false
        case .keyDown:
            if let key = classify(event) {
                handler?(key)
                return true // this keystroke belongs to hint mode
            }
            handler?(.cancel)
            return false
        default:
            return false
        }
    }

    /// nil means the keystroke isn't hint input (chorded, non-letter) and should
    /// pass through to the app while hint mode dismisses.
    private func classify(_ event: CGEvent) -> HintKeyEvent? {
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case 53: return .escape
        case 51: return .backspace
        default: break
        }
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return nil
        }
        // NSEvent does the keycode→character mapping for the user's actual
        // keyboard layout, so hints work on Dvorak/AZERTY too.
        guard let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased(),
              characters.count == 1,
              let letter = characters.first,
              letter.isASCII, letter.isLetter else {
            return nil
        }
        return .letter(letter, shifted: flags.contains(.maskShift))
    }
}
