import AppKit

/// How hint badges measure: the label font and the badge box around it.
/// Separate from the overlay view so grouping and the mode controllers can
/// size badges without referencing a view type.
@MainActor
enum BadgeMetrics {
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    static let kern: CGFloat = 0.5
    static let padding = CGSize(width: 5, height: 2)

    /// How big a badge with a label of `length` letters draws — used to lay
    /// badges out before the labels themselves exist. The font is monospaced,
    /// so only the length matters.
    static func size(forLabelLength length: Int) -> CGSize {
        let sample = NSAttributedString(
            string: String(repeating: "W", count: max(1, length)),
            attributes: [.font: font, .kern: kern]
        )
        let textSize = sample.size()
        return CGSize(
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        )
    }
}
