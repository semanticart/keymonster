import XCTest
@testable import keymonster

@MainActor
final class BookmarksFinderViewModelTests: XCTestCase {
    private func present(_ model: BookmarksFinderViewModel) {
        model.present(bookmarks: [
            Bookmark(id: 0, title: "Hacker News", url: "https://news.ycombinator.com"),
            Bookmark(id: 1, title: "GitHub", url: "https://github.com"),
            Bookmark(id: 2, title: "lobste.rs", url: "https://lobste.rs")
        ])
    }

    func testPresentSelectsTheFirstBookmark() {
        let model = BookmarksFinderViewModel()
        present(model)
        XCTAssertEqual(model.selectedID, 0)
        XCTAssertTrue(model.searchText.isEmpty)
    }

    func testTypingReselectsTheBestMatch() {
        let model = BookmarksFinderViewModel()
        present(model)
        model.searchText = "git"
        XCTAssertEqual(model.selectedID, 1)
        XCTAssertEqual(model.activateSelection()?.id, 1)
    }

    func testMoveSelectionClampsToTheEnds() {
        let model = BookmarksFinderViewModel()
        present(model)
        model.moveSelection(by: -1) // already at the top
        XCTAssertEqual(model.selectedID, 0)
        model.moveSelection(by: 99) // past the bottom
        XCTAssertEqual(model.selectedID, 2)
    }

    func testActivateReturnsNilWhenNothingMatches() {
        let model = BookmarksFinderViewModel()
        present(model)
        model.searchText = "zzz"
        XCTAssertNil(model.selectedID)
        XCTAssertNil(model.activateSelection())
    }

    func testActivateReturnsNilWhenTheListIsEmpty() {
        let model = BookmarksFinderViewModel()
        model.present(bookmarks: [])
        XCTAssertNil(model.selectedID)
        XCTAssertNil(model.activateSelection())
    }
}
