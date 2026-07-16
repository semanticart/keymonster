import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints")

/// Screenshots the screen region a zoomed hint view magnifies.
enum WindowCapture {
    /// An image of `bounds` (global display coordinates, top-left origin — the
    /// same space AX frames are in) showing what's beneath `window`, so the
    /// overlay's own badges never appear in the shot. Returns nil when Screen
    /// Recording permission is missing; the zoom view then sketches the member
    /// outlines instead of showing real pixels.
    @MainActor
    static func below(_ window: NSWindow?, bounds: CGRect) -> CGImage? {
        guard CGPreflightScreenCaptureAccess() else {
            log.info("no Screen Recording permission; hint zoom will sketch outlines")
            return nil
        }
        guard let window, window.windowNumber > 0 else { return nil }
        return CGWindowListCreateImage(
            bounds, .optionOnScreenBelowWindow, CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        )
    }
}
