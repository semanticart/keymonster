import CoreGraphics

/// The initial full-window grid: a fine, evenly tiled grid whose cells carry
/// two-character hint labels (from `HintLabels`) rather than single position
/// keys. You read the label nearest your target and type it; the chosen cell
/// becomes the region grid mode then zooms and magnifies from. Pure geometry
/// and labelling, kept apart from the overlay/tap so it can be unit tested.
enum GridHints {
    /// Roughly how big each cell should be on screen — large enough for a
    /// two-character badge, small enough that the first pick lands close.
    static let targetCellSize: CGFloat = 100

    struct Cell: Equatable {
        let label: String
        let rect: CGRect
    }

    /// `rect` tiled into cells near `targetCellSize`, labelled in reading order
    /// (cheapest-to-type labels first). Every edge is computed from `rect`, not
    /// accumulated, so the cells tile it exactly.
    static func cells(of rect: CGRect) -> [Cell] {
        let (columns, rows) = dimensions(of: rect)
        let labels = HintLabels.labels(count: columns * rows)
        return (0..<rows).flatMap { row in
            (0..<columns).map { column -> Cell in
                let minX = rect.minX + rect.width * CGFloat(column) / CGFloat(columns)
                let maxX = rect.minX + rect.width * CGFloat(column + 1) / CGFloat(columns)
                let minY = rect.minY + rect.height * CGFloat(row) / CGFloat(rows)
                let maxY = rect.minY + rect.height * CGFloat(row + 1) / CGFloat(rows)
                return Cell(
                    label: labels[row * columns + column],
                    rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                )
            }
        }
    }

    /// Columns and rows that tile `rect` into near-`targetCellSize` cells, at
    /// least one of each and never more cells in total than `HintLabels` can
    /// name with distinct labels (scaled down proportionally if they would).
    static func dimensions(of rect: CGRect) -> (columns: Int, rows: Int) {
        var columns = max(1, Int((rect.width / targetCellSize).rounded()))
        var rows = max(1, Int((rect.height / targetCellSize).rounded()))
        if columns * rows > HintLabels.maxCount {
            let shrink = (Double(columns * rows) / Double(HintLabels.maxCount)).squareRoot()
            columns = max(1, Int(Double(columns) / shrink))
            rows = max(1, Int(Double(rows) / shrink))
        }
        return (columns, rows)
    }
}
