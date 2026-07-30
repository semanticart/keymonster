import CoreGraphics

/// What pressing the scroll hotkey does, given how many scrollable panes the
/// window has. Split out of `ScrollModeController` so the rule is testable
/// without a live accessibility tree.
enum ScrollActivation: Equatable {
    /// No scrollable panes; the mode never starts.
    case none
    /// A lone pane has nothing to disambiguate, so start scrolling it at once.
    case scroll(index: Int)
    /// Several panes; label them and wait for a pick.
    case select

    static func forPaneCount(_ count: Int) -> ScrollActivation {
        switch count {
        case 0: return .none
        case 1: return .scroll(index: 0)
        default: return .select
        }
    }
}

/// Synthesizes scroll-wheel events into the active pane. The key→distance
/// mapping is pure and kept apart from the posting so it can be unit tested.
enum ScrollWheel {
    /// Pixels per keypress; key repeat turns a held key into continuous
    /// motion. Pixel units, not lines: Chromium (Slack, and Electron apps
    /// generally) ignores synthetic line-unit wheel events but honors
    /// pixel-unit ones, and native AppKit scrolls happily on either — pixels
    /// are what trackpads send.
    static let pixelStep: Int32 = 60

    /// How far one keystroke scrolls, in CGEvent's positive-is-up wheel units —
    /// j rolls the content up (wheel down), k the reverse. nil means the key
    /// doesn't scroll.
    static func pixels(for letter: Character) -> Int32? {
        switch letter {
        case "j": return -pixelStep
        case "k": return pixelStep
        default: return nil
        }
    }

    /// The window server routes scroll events to the window under the pointer,
    /// so warp there first — the same trick MouseClicker plays for clicks.
    @MainActor
    static func scroll(pixels: Int32, at point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let event = CGEvent(
            scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1,
            wheel1: pixels, wheel2: 0, wheel3: 0
        ) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
    }
}
