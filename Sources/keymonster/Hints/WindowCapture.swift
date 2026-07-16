import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "grid")

/// Copies a rectangle of the screen — the target window with the grid overlay
/// drawn on top of it — to the general pasteboard as an image.
enum WindowCapture {
    /// `bounds` is in AX (top-left origin) coordinates, the same global display
    /// space `CGWindowListCreateImage` expects, so a window's AX frame can be
    /// passed straight through. `.optionOnScreenOnly` grabs every on-screen
    /// window in the region, so the grid overlay (drawn above the window) and
    /// the window beneath it both land in the shot. Returns false if the OS
    /// hands back nothing — most likely Screen Recording permission is missing.
    @MainActor
    @discardableResult
    static func copyToPasteboard(bounds: CGRect) -> Bool {
        guard let image = CGWindowListCreateImage(
            bounds, .optionOnScreenOnly, kCGNullWindowID, [.boundsIgnoreFraming, .bestResolution]
        ) else {
            log.error("screen capture returned nil (Screen Recording permission?)")
            return false
        }

        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([nsImage])
    }
}
