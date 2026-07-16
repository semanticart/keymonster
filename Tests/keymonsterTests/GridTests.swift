import CoreGraphics
import XCTest
@testable import keymonster

final class GridDivisionTests: XCTestCase {
    // 1300 divides evenly by the top row's 13 keys; 300 by the 3 rows.
    private let rect = CGRect(x: 100, y: 200, width: 1300, height: 300)

    func testCellsMirrorTheUSKeyboardRows() {
        let cells = GridDivision.cells(of: rect)
        XCTAssertEqual(
            cells.map(\.key),
            Array("qwertyuiop[]\\") + Array("asdfghjkl;'") + Array("zxcvbnm,./")
        )

        // "q" is top-left, "\" ends the top band, and each band is a third of
        // the height (AX coordinates: y grows downward).
        XCTAssertEqual(cells[0].rect, CGRect(x: 100, y: 200, width: 100, height: 100))
        XCTAssertEqual(cells[12].rect, CGRect(x: 1300, y: 200, width: 100, height: 100))
        XCTAssertEqual(cells[13].key, "a")
        XCTAssertEqual(cells[13].rect.minY, 300)
        XCTAssertEqual(cells.last?.key, "/")
        XCTAssertEqual(cells.last?.rect.maxY, 500)
        XCTAssertEqual(cells.last?.rect.maxX, 1400)
    }

    func testRowsTileTheRectExactly() {
        // A size that doesn't divide evenly must still leave no gaps: each
        // cell's edges meet its neighbors' and the rect's. (Big enough that
        // no keys are dropped, so all three full rows are present.)
        let odd = CGRect(x: 3, y: 7, width: 1301, height: 307)
        let cells = GridDivision.cells(of: odd)
        var index = 0
        var bandTop = odd.minY
        for row in GridDivision.rows {
            let band = cells[index..<(index + row.count)]
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
        // Shift on the deciding key right-clicks, and Shift+"," types "<", so
        // shifted symbols must resolve to their unshifted key's cell.
        for (shifted, plain) in GridDivision.shiftedAliases {
            XCTAssertEqual(
                GridDivision.cell(of: rect, for: shifted),
                GridDivision.cell(of: rect, for: plain),
                "\(shifted) should name the same cell as \(plain)"
            )
            XCTAssertNotNil(GridDivision.cell(of: rect, for: shifted))
        }
    }

    func testKeysOutsideTheRowsAreRejected() {
        XCTAssertNil(GridDivision.cell(of: rect, for: "1"))
        XCTAssertNil(GridDivision.cell(of: rect, for: "="))
        XCTAssertNil(GridDivision.cell(of: rect, for: " "))
    }

    func testTwoShrinksStillLandInsideTheOriginal() {
        let window = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let first = GridDivision.cell(of: window, for: "g")!
        let second = GridDivision.cell(of: first, for: "c")!
        XCTAssertTrue(first.contains(second))
        XCTAssertTrue(window.contains(second))
        XCTAssertEqual(GridDivision.maxShrinks, 2)
    }

    func testNarrowRegionsDropRightmostKeys() {
        // 80pt fits five 16pt columns, so each row keeps its first five keys.
        let narrow = CGRect(x: 0, y: 0, width: 80, height: 300)
        let cells = GridDivision.cells(of: narrow)
        XCTAssertEqual(cells.map(\.key), Array("qwert") + Array("asdfg") + Array("zxcvb"))
        for cell in cells {
            XCTAssertGreaterThanOrEqual(cell.rect.width, GridDivision.minCellWidth)
            XCTAssertGreaterThanOrEqual(cell.rect.height, GridDivision.minCellHeight)
        }
        // Dropped keys no longer address anything.
        XCTAssertNil(GridDivision.cell(of: narrow, for: "y"))
        XCTAssertNil(GridDivision.cell(of: narrow, for: "/"))
    }

    func testShortRegionsDropBottomRows() {
        // 50pt fits two 24pt bands: the Q and A rows survive, the Z row goes.
        let short = CGRect(x: 0, y: 0, width: 1300, height: 50)
        let cells = GridDivision.cells(of: short)
        XCTAssertEqual(cells.map(\.key), Array("qwertyuiop[]\\") + Array("asdfghjkl;'"))
        XCTAssertNil(GridDivision.cell(of: short, for: "z"))
    }

    func testTinyRegionIsASingleCell() {
        let tiny = CGRect(x: 5, y: 9, width: 20, height: 18)
        let cells = GridDivision.cells(of: tiny)
        XCTAssertEqual(cells.count, 1)
        XCTAssertEqual(cells[0].key, "q")
        XCTAssertEqual(cells[0].rect, tiny)
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
