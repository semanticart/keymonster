import AppKit
import CoreGraphics
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints.keytap")

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
    /// Return or keypad Enter. Only produced when the tap's `acceptsEnter` is
    /// on (grid mode); otherwise Return passes through like any other key.
    case enter(shifted: Bool)
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
    /// The keystroke rules for the active mode; see `HintKeyClassifier`.
    var classifier = HintKeyClassifier()
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
            log.error("tap disabled (\(type.rawValue)); re-arming")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .leftMouseDown, .rightMouseDown:
            handler?(.cancel)
            return false
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if let key = classify(event) {
                log.debug("keyDown \(keyCode): swallowed as hint input")
                handler?(key)
                return true // this keystroke belongs to hint mode
            }
            log.debug("keyDown \(keyCode): not hint input, passing through")
            handler?(.cancel)
            return false
        default:
            return false
        }
    }

    /// nil means the keystroke isn't hint input (chorded, non-letter) and should
    /// pass through to the app while hint mode dismisses. The rules live in
    /// `HintKeyClassifier`, shared with the focus-capture backend.
    private func classify(_ event: CGEvent) -> HintKeyEvent? {
        guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
        return classifier.classify(nsEvent)
    }
}
