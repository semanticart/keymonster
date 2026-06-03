import XCTest
@testable import clipborg

@MainActor
final class ClipStoreTests: XCTestCase {
    func testInsertAndLoadOrdersByDateDescending() throws {
        let store = try SQLiteClipStore.inMemory()
        let older = ClipRecord(
            id: UUID(), date: Date(timeIntervalSince1970: 100), contentType: "text", textContent: "old")
        let newer = ClipRecord(
            id: UUID(), date: Date(timeIntervalSince1970: 200), contentType: "text", textContent: "new")

        try store.insert(older)
        try store.insert(newer)

        let loaded = try store.load()
        XCTAssertEqual(loaded.map(\.textContent), ["new", "old"])
    }

    func testDeleteRemovesOnlyThatRow() throws {
        let store = try SQLiteClipStore.inMemory()
        let keep = ClipRecord(
            id: UUID(), date: Date(timeIntervalSince1970: 1), contentType: "text", textContent: "keep")
        let drop = ClipRecord(
            id: UUID(), date: Date(timeIntervalSince1970: 2), contentType: "text", textContent: "drop")
        try store.insert(keep)
        try store.insert(drop)

        try store.delete(id: drop.id)

        XCTAssertEqual(try store.load().map(\.textContent), ["keep"])
    }

    func testDeleteAllEmptiesStore() throws {
        let store = try SQLiteClipStore.inMemory()
        try store.insert(ClipRecord(id: UUID(), date: Date(), contentType: "text", textContent: "a"))
        try store.deleteAll()
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testHistoryPersistsAcrossReload() throws {
        let store = try SQLiteClipStore.inMemory()

        let history = ClipboardHistory()
        history.configure(store: store)
        history.add(.text("remembered"))

        // A fresh history backed by the same store reloads what was saved.
        let reloaded = ClipboardHistory()
        reloaded.configure(store: store)

        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.items.first?.content, .text("remembered"))
    }

    func testHistoryDedupMovesExistingToFrontAndPersists() throws {
        let store = try SQLiteClipStore.inMemory()
        let history = ClipboardHistory()
        history.configure(store: store)

        history.add(.text("a"))
        history.add(.text("b"))
        history.add(.text("a")) // duplicate of the oldest

        XCTAssertEqual(history.items.map(\.content), [.text("a"), .text("b")])

        let reloaded = ClipboardHistory()
        reloaded.configure(store: store)
        XCTAssertEqual(reloaded.items.map(\.content), [.text("a"), .text("b")])
    }
}
