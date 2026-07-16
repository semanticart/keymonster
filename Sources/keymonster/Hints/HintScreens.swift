import AppKit

/// Where hint badges are allowed to go: anywhere on the screen showing the
/// target window, not just inside the window itself. Elements flush against a
/// window edge then get labels hanging just outside it instead of clamped
/// (and colliding) within.
@MainActor
enum HintScreens {
    /// The frame (AX top-left coordinates) of the screen showing most of
    /// `windowFrame`. Falls back to the window frame itself when no screen
    /// overlaps it.
    static func bounds(around windowFrame: CGRect) -> CGRect {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return windowFrame }
        // cocoaRect flips between Cocoa and AX coordinates in either direction.
        let frames = NSScreen.screens.map {
            HintGeometry.cocoaRect(fromAX: $0.frame, primaryScreenHeight: primaryHeight)
        }
        return HintGeometry.bestContainer(for: windowFrame, among: frames) ?? windowFrame
    }
}
