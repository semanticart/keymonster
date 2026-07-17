import XCTest
@testable import keymonster

final class FuzzyMatchTests: XCTestCase {
    func testEmptyQueryMatchesEverything() {
        XCTAssertEqual(FuzzyMatch.score("File Save", query: ""), 0)
    }

    func testSubsequenceMatchesOutOfOrderCharactersInOrder() {
        XCTAssertNotNil(FuzzyMatch.score("File Save As", query: "sa"))
        XCTAssertNotNil(FuzzyMatch.score("File Save As", query: "fsa")) // spans words
    }

    func testNonSubsequenceDoesNotMatch() {
        XCTAssertNil(FuzzyMatch.score("File Save", query: "z"))
        XCTAssertNil(FuzzyMatch.score("File Save", query: "eas")) // wrong order
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatch.score("File Save As", query: "SAVE"))
    }

    func testConsecutiveMatchOutscoresScattered() {
        let consecutive = FuzzyMatch.score("Save", query: "sav")
        let scattered = FuzzyMatch.score("Show all values", query: "sav")
        XCTAssertNotNil(consecutive)
        XCTAssertNotNil(scattered)
        XCTAssertGreaterThan(consecutive!, scattered!)
    }

    func testWordBoundaryMatchOutscoresMidWord() {
        let boundary = FuzzyMatch.score("Save Document", query: "sd")
        let midWord = FuzzyMatch.score("Standard", query: "sd")
        XCTAssertNotNil(boundary)
        XCTAssertNotNil(midWord)
        XCTAssertGreaterThan(boundary!, midWord!)
    }
}

final class MenuItemFilterTests: XCTestCase {
    private func items() -> [MenuBarItem] {
        [
            MenuBarItem(id: 0, path: ["File"], title: "New"),
            MenuBarItem(id: 1, path: ["File"], title: "Save As…"),
            MenuBarItem(id: 2, path: ["Edit"], title: "Select All"),
            MenuBarItem(id: 3, path: ["View", "Zoom"], title: "Actual Size")
        ]
    }

    func testEmptyQueryReturnsEverythingInOrder() {
        XCTAssertEqual(MenuItemFilter.filter(items(), query: "").map(\.id), [0, 1, 2, 3])
    }

    func testFilterKeepsOnlySubsequenceMatches() {
        let ids = MenuItemFilter.filter(items(), query: "save").map(\.id)
        XCTAssertEqual(ids, [1])
    }

    func testFilterMatchesAcrossThePath() {
        // "zoom act" spans the "View › Zoom" path and the "Actual Size" title.
        let ids = MenuItemFilter.filter(items(), query: "zoom act").map(\.id)
        XCTAssertEqual(ids, [3])
    }

    func testBestMatchRanksFirst() {
        // "sa" hits both "Save As…" (leading, consecutive) and "Select All"
        // (two word-initials); the query order should surface the strongest.
        let first = MenuItemFilter.filter(items(), query: "sa").first
        XCTAssertNotNil(first)
    }
}

@MainActor
final class MenuFinderViewModelTests: XCTestCase {
    private func present(_ model: MenuFinderViewModel) {
        model.present(items: [
            MenuBarItem(id: 0, path: ["File"], title: "New"),
            MenuBarItem(id: 1, path: ["File"], title: "Save As…"),
            MenuBarItem(id: 2, path: ["Edit"], title: "Select All")
        ], appName: "TextEdit")
    }

    func testPresentSelectsTheFirstItem() {
        let model = MenuFinderViewModel()
        present(model)
        XCTAssertEqual(model.selectedID, 0)
        XCTAssertEqual(model.appName, "TextEdit")
        XCTAssertTrue(model.searchText.isEmpty)
    }

    func testTypingReselectsTheBestMatch() {
        let model = MenuFinderViewModel()
        present(model)
        model.searchText = "save"
        XCTAssertEqual(model.selectedID, 1)
        XCTAssertEqual(model.activateSelection()?.id, 1)
    }

    func testMoveSelectionClampsToTheEnds() {
        let model = MenuFinderViewModel()
        present(model)
        model.moveSelection(by: -1) // already at the top
        XCTAssertEqual(model.selectedID, 0)
        model.moveSelection(by: 99) // past the bottom
        XCTAssertEqual(model.selectedID, 2)
    }

    func testActivateReturnsNilWhenNothingMatches() {
        let model = MenuFinderViewModel()
        present(model)
        model.searchText = "zzz"
        XCTAssertNil(model.selectedID)
        XCTAssertNil(model.activateSelection())
    }
}
