import XCTest
@testable import keymonster

final class BookmarksStoreTests: XCTestCase {
    private var directory: URL!
    private var url: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keymonster-bookmarks-store-test-\(UUID().uuidString)")
        url = directory.appendingPathComponent("bookmarks.csv")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testEnsureExistsCreatesAHeaderOnlyFileWhenMissing() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try BookmarksStore.ensureExists(at: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "title,url\n")
    }

    func testEnsureExistsNeverTouchesAnExistingFile() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "Hacker News,https://news.ycombinator.com\n".write(to: url, atomically: true, encoding: .utf8)

        try BookmarksStore.ensureExists(at: url)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "Hacker News,https://news.ycombinator.com\n")
    }

    func testLoadReturnsEmptyForAMissingFileWithoutCreatingIt() {
        XCTAssertEqual(BookmarksStore.load(from: url), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLoadRoundTripsAHandWrittenCSVIncludingAQuotedTitle() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        title,url
        Hacker News,https://news.ycombinator.com
        "Foo, Bar",https://example.com
        """.write(to: url, atomically: true, encoding: .utf8)

        let bookmarks = BookmarksStore.load(from: url)

        XCTAssertEqual(bookmarks.map(\.title), ["Hacker News", "Foo, Bar"])
        XCTAssertEqual(bookmarks.map(\.url), ["https://news.ycombinator.com", "https://example.com"])
    }
}
