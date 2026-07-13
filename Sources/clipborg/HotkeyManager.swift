import Carbon.HIToolbox
import Foundation

// Module-level globals so the C callback can reach them without captures. Keyed
// by the hotkey id we assign at registration time, so a single handler can fan
// out to many distinct shortcuts.
nonisolated(unsafe) private var _hotkeyCallbacks: [UInt32: () -> Void] = [:]
nonisolated(unsafe) private var _eventHandlerRef: EventHandlerRef?

private func carbonHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotkeyID = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID
    )
    guard status == noErr else { return status }
    let id = hotkeyID.id
    DispatchQueue.main.async { _hotkeyCallbacks[id]?() }
    return noErr
}

/// A single global shortcut and the action to run when it fires.
struct HotkeyBinding {
    let shortcut: Shortcut
    let action: () -> Void
}

@MainActor
final class HotkeyManager {
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1

    /// Replace every registered hotkey with `bindings`. Re-registering wholesale
    /// keeps the callback table in sync with settings without per-entry bookkeeping.
    func register(_ bindings: [HotkeyBinding]) {
        unregisterAll()
        installHandlerIfNeeded()

        for binding in bindings {
            let id = nextID
            nextID += 1
            _hotkeyCallbacks[id] = binding.action
            let hotkeyID = EventHotKeyID(signature: 0x434C5047 /* CLPG */, id: id)
            var ref: EventHotKeyRef?
            RegisterEventHotKey(
                binding.shortcut.keyCode, binding.shortcut.carbonModifiers,
                hotkeyID, GetApplicationEventTarget(), 0, &ref
            )
            hotKeyRefs[id] = ref
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        _hotkeyCallbacks.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard _eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(), carbonHotKeyHandler,
            1, &spec, nil, &_eventHandlerRef
        )
    }
}
