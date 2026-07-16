import XCTest
@testable import keymonster

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

    func testHistoryDedupImagesByDataEquality() throws {
        let store = try SQLiteClipStore.inMemory()
        let history = ClipboardHistory()
        history.configure(store: store)

        let imageA = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let imageB = Data([0xFA, 0xCE, 0xFE, 0xED])

        history.add(.image(imageA))
        history.add(.image(imageB))
        // Same bytes as imageA but a distinct instance — dedup must compare by
        // value, not identity, and without decoding either as an NSImage.
        history.add(.image(Data([0xDE, 0xAD, 0xBE, 0xEF])))

        XCTAssertEqual(history.items.map(\.content), [.image(imageA), .image(imageB)])
    }
}
