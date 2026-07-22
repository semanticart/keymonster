import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints")

/// Screenshots the screen region a zoomed hint view magnifies.
enum WindowCapture {
    /// An image of `bounds` (global display coordinates, top-left origin — the
    /// same space AX frames are in) showing what's beneath `window`, so the
    /// overlay's own badges never appear in the shot. Without Screen Recording
    /// permission this raises the system prompt and returns nil; the zoom view
    /// sketches the member outlines until the grant takes effect (macOS applies
    /// it on relaunch).
    @MainActor
    static func below(_ window: NSWindow?, bounds: CGRect) -> CGImage? {
        if !CGPreflightScreenCaptureAccess() {
            log.info("no Screen Recording permission; prompting")
            guard CGRequestScreenCaptureAccess() else { return nil }
        }
        guard let window, window.windowNumber > 0 else { return nil }
        return CGWindowListCreateImage(
            bounds, .optionOnScreenBelowWindow, CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]
        )
    }
}
