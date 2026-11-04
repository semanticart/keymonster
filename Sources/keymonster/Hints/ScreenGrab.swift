import AppKit
import ScreenCaptureKit

/// Where on which display a global-coordinate rect should be captured.
struct CapturePlan: Equatable {
    /// Index into the displays the plan was made against.
    let displayIndex: Int
    /// The part of the rect on that display, in the display's own coordinates
    /// (points, top-left origin) — what `SCStreamConfiguration.sourceRect` wants.
    let source: CGRect
}

enum CaptureGeometry {
    /// Picks the display holding most of `bounds` and clips to it. A capture
    /// is one display's content, so a rect straddling displays keeps only the
    /// dominant side. `displays` are frames in the same global top-left space
    /// as `bounds` (AX coordinates). Nil when `bounds` touches none of them.
    static func plan(bounds: CGRect, displays: [CGRect]) -> CapturePlan? {
        var best: (index: Int, clipped: CGRect)?
        for (index, frame) in displays.enumerated() {
            let clipped = bounds.intersection(frame)
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { continue }
            if clipped.width * clipped.height > (best.map { $0.clipped.width * $0.clipped.height } ?? 0) {
                best = (index, clipped)
            }
        }
        guard let best else { return nil }
        let frame = displays[best.index]
        return CapturePlan(
            displayIndex: best.index,
            source: best.clipped.offsetBy(dx: -frame.origin.x, dy: -frame.origin.y)
        )
    }
}

/// Screenshots a screen region with ScreenCaptureKit. Needs Screen Recording
/// permission; without it (or on any failure) every call yields nil.
enum ScreenGrab {
    /// An image of `bounds` (global top-left coordinates, like AX frames) at
    /// the display's native pixel density, leaving out the window numbered
    /// `excluding` — typically our own overlay, so its badges never appear in
    /// the shot.
    static func image(of bounds: CGRect, excluding windowID: CGWindowID?) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let plan = CaptureGeometry.plan(
                bounds: bounds, displays: content.displays.map(\.frame)
            ) else { return nil }
            let skipped = content.windows.filter { $0.windowID == windowID }
            let filter = SCContentFilter(
                display: content.displays[plan.displayIndex], excludingWindows: skipped
            )
            let config = SCStreamConfiguration()
            config.sourceRect = plan.source
            let scale = CGFloat(filter.pointPixelScale)
            config.width = max(1, Int((plan.source.width * scale).rounded()))
            config.height = max(1, Int((plan.source.height * scale).rounded()))
            config.showsCursor = false
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
        } catch {
            return nil
        }
    }

    /// Blocking variant for synchronous debug tooling with no run loop to
    /// await on. Never call from code that the capture itself depends on.
    static func imageBlocking(of bounds: CGRect, excluding windowID: CGWindowID? = nil) -> CGImage? {
        final class Box: @unchecked Sendable { var image: CGImage? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.image = await image(of: bounds, excluding: windowID)
            done.signal()
        }
        done.wait()
        return box.image
    }
}
