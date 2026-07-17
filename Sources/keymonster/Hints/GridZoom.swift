import CoreGraphics

/// Geometry for grid mode's loupe: once you've zoomed past the first grid, the
/// active region is magnified to fill the window so you can read what sits under
/// the keys before committing to a click. Pure math, kept apart from the overlay
/// so it can be unit tested.
enum GridZoom {
    /// The panel covers at most this much of the window on each axis, so it
    /// never runs edge to edge and keeps a little slack to center within.
    private static let maxCoverage: CGFloat = 0.9

    /// How much `region` magnifies to fill `bounds` without distortion — the
    /// smaller of the two per-axis ratios, never below 1x. The first grid
    /// already fills the window, so it comes back as 1x and isn't magnified.
    static func scale(magnifying region: CGRect, into bounds: CGRect) -> CGFloat {
        guard region.width > 0, region.height > 0 else { return 1 }
        return max(1, min(
            bounds.width * maxCoverage / region.width,
            bounds.height * maxCoverage / region.height
        ))
    }

    /// Where the magnified `region` draws: scaled uniformly and centered on the
    /// region's own middle, so the cell you just picked stays put and simply
    /// grows instead of jumping to the center of the window. Nudged back inside
    /// `bounds` when the region sits near an edge.
    static func panel(magnifying region: CGRect, into bounds: CGRect) -> CGRect {
        let scale = scale(magnifying: region, into: bounds)
        let size = CGSize(width: region.width * scale, height: region.height * scale)
        var origin = CGPoint(x: region.midX - size.width / 2, y: region.midY - size.height / 2)
        origin.x = min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width))
        origin.y = min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        return CGRect(origin: origin, size: size)
    }
}
