import CoreGraphics
import Foundation

/// Spreads each keypress's scroll distance over several small wheel events so
/// motion looks continuous instead of jumping a full step per key repeat. Pure
/// arithmetic, no clock: the caller ticks it at a steady rate and posts what
/// comes back.
struct ScrollAnimator {
    /// Fraction of the remaining distance emitted per tick. A tap eases out;
    /// a held key settles where each tick's drain matches the repeat's top-up,
    /// so overall speed is the same as posting every step at once.
    static let drainDivisor: Int32 = 4

    /// Pixels still to scroll, signed like the wheel (positive is up).
    private(set) var pending: Int32 = 0

    var isIdle: Bool { pending == 0 }

    /// Queues `pixels` more. Reversing direction drops what was left in the old
    /// one, so k right after j turns around at once instead of first finishing
    /// the earlier glide.
    mutating func add(_ pixels: Int32) {
        if pending != 0, (pending < 0) != (pixels < 0) { pending = 0 }
        pending += pixels
    }

    /// The pixels to post this tick, in wheel units; 0 once drained.
    mutating func tick() -> Int32 {
        guard pending != 0 else { return 0 }
        let size = max(1, abs(pending) / Self.drainDivisor)
        let step = pending < 0 ? -size : size
        pending -= step
        return step
    }

    /// Forgets anything queued.
    mutating func cancel() { pending = 0 }
}

/// Drives a `ScrollAnimator` off a timer, posting its steps as wheel events at
/// one point.
@MainActor
final class SmoothScroller {
    /// ~120 Hz: finer than the display refresh so steps never queue up behind a
    /// frame, coarse enough to stay cheap.
    private static let interval: TimeInterval = 1.0 / 120

    private var animator = ScrollAnimator()
    private var point = CGPoint.zero
    private var timer: Timer?

    /// Queues `pixels` of scrolling at `point` and starts the timer if idle.
    /// The pointer is warped here, once per keypress, not per step.
    func scroll(pixels: Int32, at point: CGPoint) {
        self.point = point
        ScrollWheel.warp(to: point)
        animator.add(pixels)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Drops anything still queued and stops the timer.
    func cancel() {
        animator.cancel()
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let step = animator.tick()
        if step != 0 { ScrollWheel.post(pixels: step, at: point) }
        if animator.isIdle { cancel() }
    }
}
