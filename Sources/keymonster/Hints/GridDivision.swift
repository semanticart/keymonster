import CoreGraphics

/// Divides a rectangle into cells mirroring the US keyboard's three letter
/// rows: Q…\ across the top, A…' in the middle, Z…/ along the bottom, so the
/// key under your finger names the cell in the same position on screen. Pure
/// logic, kept apart from the overlay/tap machinery so it can be unit tested.
enum GridDivision {
    /// The unshifted US keys of each row, top to bottom. Rows have different
    /// key counts, so each horizontal band gets its own column widths.
    static let rows: [[Character]] = [
        Array("qwertyuiop[]\\"),
        Array("asdfghjkl;'"),
        Array("zxcvbnm,./")
    ]

    /// A keypress zooms the region in at most this many times; once the limit
    /// is reached the next keypress clicks its cell instead.
    static let maxShrinks = 2

    /// Cells smaller than this can't fit a readable key badge, so keys are
    /// dropped — rightmost first, then the bottom rows — until every cell is
    /// at least this big. A badge is one character, taller than it is wide,
    /// so cells can be a fair bit narrower than they are short.
    static let minCellWidth: CGFloat = 16
    static let minCellHeight: CGFloat = 24

    /// What Shift turns each unshifted key into. Shift on the deciding key
    /// requests a right-click, so the shifted symbol must still name its key.
    /// (Letters don't need entries: the key tap lowercases them.)
    static let shiftedAliases: [Character: Character] = [
        "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'",
        "<": ",", ">": ".", "?": "/"
    ]

    struct Cell: Equatable {
        let key: Character
        let rect: CGRect
    }

    /// All cells of `rect` in keyboard order, using only as many keys per row
    /// (and as many rows) as fit at the minimum cell size. Every edge is
    /// computed from the enclosing rect (not accumulated) so the cells tile it
    /// exactly.
    static func cells(of rect: CGRect) -> [Cell] {
        let bands = fitting(rows.count, into: rect.height, minimum: minCellHeight)
        return rows.prefix(bands).enumerated().flatMap { rowIndex, keys -> [Cell] in
            let minY = rect.minY + rect.height * CGFloat(rowIndex) / CGFloat(bands)
            let maxY = rect.minY + rect.height * CGFloat(rowIndex + 1) / CGFloat(bands)
            let columns = fitting(keys.count, into: rect.width, minimum: minCellWidth)
            return keys.prefix(columns).enumerated().map { column, key in
                let minX = rect.minX + rect.width * CGFloat(column) / CGFloat(columns)
                let maxX = rect.minX + rect.width * CGFloat(column + 1) / CGFloat(columns)
                return Cell(key: key, rect: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
            }
        }
    }

    /// How many of `count` cells fit across `span` without dropping below the
    /// minimum cell size. At least one: a region too small to split any further
    /// still needs a cell to click.
    private static func fitting(_ count: Int, into span: CGFloat, minimum: CGFloat) -> Int {
        max(1, min(count, Int(span / minimum)))
    }

    /// The cell of `rect` addressed by `key`, or nil for a key outside the
    /// three keyboard rows.
    static func cell(of rect: CGRect, for key: Character) -> CGRect? {
        let normalized = shiftedAliases[key] ?? key
        return cells(of: rect).first { $0.key == normalized }?.rect
    }
}
