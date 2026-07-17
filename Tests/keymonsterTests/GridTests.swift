import CoreGraphics
import XCTest
@testable import keymonster

final class GridDivisionTests: XCTestCase {
    // 1000 divides evenly by the 10-column cap; 300 by the 3 rows.
    private let rect = CGRect(x: 100, y: 200, width: 1000, height: 300)

    func testCellsMirrorTheUSKeyboardRows() {
        let cells = GridDivision.cells(of: rect)
        // Each row keeps only its leftmost `maxColumns` keys.
        XCTAssertEqual(
            cells.map(\.key),
            Array("qwertyuiop") + Array("asdfghjkl;") + Array("zxcvbnm,./")
        )

        // "q" is top-left, "p" ends the top band, and each band is a third of
        // the height (AX coordinates: y grows downward).
        XCTAssertEqual(cells[0].rect, CGRect(x: 100, y: 200, width: 100, height: 100))
        XCTAssertEqual(cells[9].rect, CGRect(x: 1000, y: 200, width: 100, height: 100))
        XCTAssertEqual(cells[10].key, "a")
        XCTAssertEqual(cells[10].rect.minY, 300)
        XCTAssertEqual(cells.last?.key, "/")
        XCTAssertEqual(cells.last?.rect.maxY, 500)
        XCTAssertEqual(cells.last?.rect.maxX, 1100)
    }

    func testRowsTileTheRectExactly() {
        // A size that doesn't divide evenly must still leave no gaps: each
        // cell's edges meet its neighbors' and the rect's. (Wide enough that
        // every row fills the 10-column cap.)
        let odd = CGRect(x: 3, y: 7, width: 1001, height: 307)
        let cells = GridDivision.cells(of: odd)
        var index = 0
        var bandTop = odd.minY
        for row in GridDivision.rows {
            let band = cells[index..<(index + GridDivision.maxColumns)]
            XCTAssertEqual(band.first?.rect.minX, odd.minX)
            XCTAssertEqual(band.last?.rect.maxX, odd.maxX)
            for cell in band {
                XCTAssertEqual(cell.rect.minY, bandTop)
                if cell.key != row.first {
                    XCTAssertEqual(cell.rect.minX, cells[index - 1].rect.maxX)
                }
                index += 1
            }
            bandTop = band.first!.rect.maxY
        }
        XCTAssertEqual(bandTop, odd.maxY)
    }

    func testCellForKeyMatchesCellsOrder() {
        for cell in GridDivision.cells(of: rect) {
            XCTAssertEqual(GridDivision.cell(of: rect, for: cell.key), cell.rect)
        }
    }

    func testShiftedSymbolsAliasTheirKeys() {
        // A shifted symbol always resolves to its unshifted key's cell — so
        // Shift on the deciding key right-clicks the same spot the plain key
        // names, whether that key is within the cap (both resolve) or past it
        // (both nil). The parity is what matters.
        for (shifted, plain) in GridDivision.shiftedAliases {
            XCTAssertEqual(
                GridDivision.cell(of: rect, for: shifted),
                GridDivision.cell(of: rect, for: plain),
                "\(shifted) should name the same cell as \(plain)"
            )
        }
    }

    func testColumnsPastTheCapAreDropped() {
        // Only keys past the 10th column of a row fall off, however large the
        // region — the letters all survive; "[ ] \ '" don't.
        let wide = CGRect(x: 0, y: 0, width: 2000, height: 600)
        for key in "[]\\'" {
            XCTAssertNil(GridDivision.cell(of: wide, for: key), "\(key) should be dropped")
        }
        for shifted in "{}|\"" {
            XCTAssertNil(GridDivision.cell(of: wide, for: shifted), "\(shifted) should be dropped")
        }
        // Punctuation within the cap still resolves.
        for kept in ";,./" {
            XCTAssertNotNil(GridDivision.cell(of: wide, for: kept), "\(kept) should be kept")
        }
    }

    func testTwoZoomsKeepMoreThanOneColumn() {
        // The reason the cap exists: a couple of zooms in, the grid must still
        // let you pick left or right, not collapse to a single vertical strip.
        let window = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let first = GridDivision.cell(of: window, for: "g")!
        let second = GridDivision.cell(of: first, for: "g")!
        let columns = Set(GridDivision.cells(of: second).map(\.rect.minX)).count
        XCTAssertGreaterThan(columns, 1)
    }

    func testKeysOutsideTheRowsAreRejected() {
        XCTAssertNil(GridDivision.cell(of: rect, for: "1"))
        XCTAssertNil(GridDivision.cell(of: rect, for: "="))
        XCTAssertNil(GridDivision.cell(of: rect, for: " "))
    }

    func testEveryShrinkStaysInsideTheOriginal() {
        let window = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let first = GridDivision.cell(of: window, for: "g")!
        let second = GridDivision.cell(of: first, for: "c")!
        // By the third grid the region is only a couple of columns wide, so the
        // third key has to be one of them ("s" is the second column).
        let third = GridDivision.cell(of: second, for: "s")!
        XCTAssertTrue(first.contains(second))
        XCTAssertTrue(second.contains(third))
        XCTAssertTrue(window.contains(third))
        XCTAssertEqual(GridDivision.maxShrinks, 5)
    }

    func testNarrowRegionsDropRightmostKeys() {
        // 12pt fits six 2pt columns — fewer than the cap — so every row keeps
        // just its first six keys.
        let narrow = CGRect(x: 0, y: 0, width: 12, height: 300)
        let cells = GridDivision.cells(of: narrow)
        XCTAssertEqual(
            cells.map(\.key),
            Array("qwerty") + Array("asdfgh") + Array("zxcvbn")
        )
        for cell in cells {
            XCTAssertGreaterThanOrEqual(cell.rect.width, GridDivision.minCellWidth)
            XCTAssertGreaterThanOrEqual(cell.rect.height, GridDivision.minCellHeight)
        }
        // Dropped keys no longer address anything.
        XCTAssertNil(GridDivision.cell(of: narrow, for: "u"))
        XCTAssertNil(GridDivision.cell(of: narrow, for: "j"))
    }

    func testShortRegionsDropBottomRows() {
        // 8pt fits two 3pt bands: the Q and A rows survive, the Z row goes.
        // Each surviving band keeps its first `maxColumns` keys.
        let short = CGRect(x: 0, y: 0, width: 1300, height: 8)
        let cells = GridDivision.cells(of: short)
        XCTAssertEqual(cells.map(\.key), Array("qwertyuiop") + Array("asdfghjkl;"))
        XCTAssertNil(GridDivision.cell(of: short, for: "z"))
    }

    func testTinyRegionIsASingleCell() {
        let tiny = CGRect(x: 5, y: 9, width: 3, height: 5)
        let cells = GridDivision.cells(of: tiny)
        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells[0].key, "q")
        XCTAssertEqual(cells[0].rect, tiny)
    }
}

final class GridHintsTests: XCTestCase {
    func testCellsTileTheWindowWithTwoCharacterLabels() {
        let window = CGRect(x: 100, y: 50, width: 1600, height: 900)
        let (columns, rows) = GridHints.dimensions(of: window)
        let cells = GridHints.cells(of: window)

        XCTAssertEqual(cells.count, columns * rows)
        // A normal window has more cells than single letters, so every label is
        // a two-character pair, and no label repeats.
        XCTAssertTrue(cells.allSatisfy { $0.label.count == 2 })
        XCTAssertEqual(Set(cells.map(\.label)).count, cells.count)

        // The cells cover the window edge to edge with no gaps.
        XCTAssertEqual(cells.first?.rect.minX, window.minX)
        XCTAssertEqual(cells.first?.rect.minY, window.minY)
        XCTAssertEqual(cells.last?.rect.maxX, window.maxX)
        XCTAssertEqual(cells.last?.rect.maxY, window.maxY)
        for cell in cells {
            XCTAssertGreaterThanOrEqual(cell.rect.minX, window.minX)
            XCTAssertLessThanOrEqual(cell.rect.maxX, window.maxX + 0.0001)
        }
    }

    func testCellsStayNearTheTargetSize() {
        let window = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let cells = GridHints.cells(of: window)
        // Each cell is within half a target of the intended size — fine enough
        // to land close, coarse enough for a readable label.
        for cell in cells {
            XCTAssertEqual(cell.rect.width, GridHints.targetCellSize, accuracy: GridHints.targetCellSize)
            XCTAssertEqual(cell.rect.height, GridHints.targetCellSize, accuracy: GridHints.targetCellSize)
        }
    }

    func testHugeWindowsStayWithinTheLabelSupply() {
        // A wall-sized window would want thousands of cells; it's capped to what
        // two-letter labels can name, so every cell still gets a unique label.
        let huge = CGRect(x: 0, y: 0, width: 8000, height: 5000)
        let cells = GridHints.cells(of: huge)
        XCTAssertLessThanOrEqual(cells.count, HintLabels.maxCount)
        XCTAssertEqual(Set(cells.map(\.label)).count, cells.count)
    }
}

final class GridZoomTests: XCTestCase {
    private let window = CGRect(x: 0, y: 0, width: 700, height: 300)

    func testTheWholeWindowIsNotMagnified() {
        // The first grid already fills the window, so it stays 1x and the panel
        // is the window itself.
        XCTAssertEqual(GridZoom.scale(magnifying: window, into: window), 1)
        XCTAssertEqual(GridZoom.panel(magnifying: window, into: window), window)
    }

    func testARegionMagnifiesByItsTighterAxisAndStaysCenteredOnItself() {
        // A centered cell: height is the tighter axis, so 0.9 * 300 / 100 = 2.7
        // wins, and the panel keeps the cell's own center rather than jumping to
        // the middle of the window.
        let cell = CGRect(x: 300, y: 100, width: 100, height: 100)
        XCTAssertEqual(GridZoom.scale(magnifying: cell, into: window), 2.7, accuracy: 0.0001)

        let panel = GridZoom.panel(magnifying: cell, into: window)
        XCTAssertEqual(panel.midX, cell.midX, accuracy: 0.0001)
        XCTAssertEqual(panel.midY, cell.midY, accuracy: 0.0001)
    }

    func testAPanelNearAnEdgeIsNudgedInside() {
        // A cell against the right edge can't stay centered on itself without
        // spilling out, so it slides just inside the window.
        let cell = CGRect(x: 660, y: 130, width: 40, height: 40)
        let panel = GridZoom.panel(magnifying: cell, into: window)
        XCTAssertGreaterThanOrEqual(panel.minX, window.minX)
        XCTAssertLessThanOrEqual(panel.maxX, window.maxX)
        XCTAssertGreaterThanOrEqual(panel.minY, window.minY)
        XCTAssertLessThanOrEqual(panel.maxY, window.maxY)
    }

    func testDegenerateRegionsStayAtOneX() {
        XCTAssertEqual(GridZoom.scale(magnifying: .zero, into: window), 1)
    }
}

final class GridShortcutSettingsTests: XCTestCase {
    @MainActor
    func testGridShortcutPersistsAcrossInstances() {
        let suite = "grid-settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.gridShortcut = Shortcut(keyCode: 5, carbonModifiers: 0x0100 | 0x0800)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.gridShortcut, Shortcut(keyCode: 5, carbonModifiers: 0x0100 | 0x0800))

        reloaded.gridShortcut = nil
        XCTAssertNil(AppSettings(defaults: defaults).gridShortcut)
    }
}
