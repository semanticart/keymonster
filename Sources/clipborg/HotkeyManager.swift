import Carbon.HIToolbox
import Foundation

// Module-level globals so the C callback can reach them without captures.
nonisolated(unsafe) private var _hotkeyCallback: (() -> Void)?
nonisolated(unsafe) private var _eventHandlerRef: EventHandlerRef?

private func carbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async { _hotkeyCallback?() }
    return noErr
}

@MainActor
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?

    func register(_ shortcut: Shortcut, onActivate: @escaping () -> Void) {
        unregister()
        _hotkeyCallback = onActivate

        if _eventHandlerRef == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            InstallEventHandler(
                GetApplicationEventTarget(), carbonHotKeyHandler,
                1, &spec, nil, &_eventHandlerRef
            )
        }

        let hotkeyID = EventHotKeyID(signature: 0x434C5047 /* CLPG */, id: 1)
        RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers,
            hotkeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        _hotkeyCallback = nil
    }
}
