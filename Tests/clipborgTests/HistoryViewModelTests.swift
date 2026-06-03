import XCTest
@testable import clipborg

@MainActor
final class HistoryViewModelTests: XCTestCase {
    private func textItem(_ text: String, app: String? = nil) -> ClipItem {
        ClipItem(
            content: .text(text), date: Date(),
            sourceAppName: app, sourceAppBundleID: nil, sourceAppIcon: nil
        )
    }

    private func fileItem(_ path: String) -> ClipItem {
        ClipItem(
            content: .fileURLs([URL(fileURLWithPath: path)]), date: Date(),
            sourceAppName: nil, sourceAppBundleID: nil, sourceAppIcon: nil
        )
    }

    // MARK: - Filtering

    func testEmptyQueryReturnsEverything() {
        let items = [textItem("apple"), textItem("banana")]
        XCTAssertEqual(HistoryViewModel.filter(items, query: "  ").count, 2)
    }

    func testFilterMatchesTextCaseInsensitively() {
        let items = [textItem("Apple Pie"), textItem("Banana")]
        let matched = HistoryViewModel.filter(items, query: "apple")
        XCTAssertEqual(matched.count, 1)
        XCTAssertEqual(matched.first?.content, .text("Apple Pie"))
    }

    func testFilterMatchesFileName() {
        let items = [fileItem("/tmp/report.pdf"), fileItem("/tmp/photo.png")]
        XCTAssertEqual(HistoryViewModel.filter(items, query: "report").count, 1)
    }

    func testFilterMatchesSourceAppName() {
        let items = [textItem("hello", app: "Safari"), textItem("world", app: "Mail")]
        XCTAssertEqual(HistoryViewModel.filter(items, query: "safari").count, 1)
    }

    // MARK: - Selection navigation

    private func populatedViewModel() -> HistoryViewModel {
        let history = ClipboardHistory()
        // Added oldest-first so the newest ("cherry") ends up at index 0.
        history.add(.text("apple"))
        history.add(.text("banana"))
        history.add(.text("cherry"))
        return HistoryViewModel(history: history)
    }

    func testPresentationSelectsFirstItem() {
        let model = populatedViewModel()
        model.prepareForPresentation()
        XCTAssertEqual(model.filteredItems.first?.id, model.selectedID)
    }

    func testCtrlNAndCtrlPMoveAndClamp() {
        let model = populatedViewModel()
        model.prepareForPresentation()
        let ids = model.filteredItems.map(\.id)

        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedID, ids[1])
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedID, ids[2])
        // Clamp at the bottom.
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedID, ids[2])

        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedID, ids[1])
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedID, ids[0])
        // Clamp at the top.
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedID, ids[0])
    }

    func testEditingSearchReselectsFirstMatch() {
        let model = populatedViewModel()
        model.prepareForPresentation()
        model.searchText = "banana"
        XCTAssertEqual(model.filteredItems.count, 1)
        XCTAssertEqual(model.selectedID, model.filteredItems.first?.id)
    }

    func testActivateSelectionReportsWhetherSomethingWasCopied() {
        let model = populatedViewModel()
        model.prepareForPresentation()
        XCTAssertTrue(model.activateSelection())

        model.searchText = "no-such-content"
        XCTAssertNil(model.selectedID)
        XCTAssertFalse(model.activateSelection())
    }
}
