import XCTest
@testable import keymonster

final class BookmarkResolvedURLTests: XCTestCase {
    func testAbsolutePathIsLocal() {
        let bookmark = Bookmark(id: 0, title: "Repo", url: "/Users/ship/src/keymonster")
        XCTAssertTrue(bookmark.isLocalPath)
        XCTAssertEqual(bookmark.resolvedURL, URL(fileURLWithPath: "/Users/ship/src/keymonster"))
    }

    func testTildePathIsLocalAndExpanded() {
        let bookmark = Bookmark(id: 0, title: "Downloads", url: "~/Downloads")
        XCTAssertTrue(bookmark.isLocalPath)
        let expected = URL(fileURLWithPath: ("~/Downloads" as NSString).expandingTildeInPath)
        XCTAssertEqual(bookmark.resolvedURL, expected)
    }

    func testRemoteURLIsNotLocal() {
        let bookmark = Bookmark(id: 0, title: "Hacker News", url: "https://news.ycombinator.com")
        XCTAssertFalse(bookmark.isLocalPath)
        XCTAssertEqual(bookmark.resolvedURL, URL(string: "https://news.ycombinator.com"))
    }

    func testBareDomainWithoutSchemeIsNotTreatedAsLocal() {
        // No leading "/" or "~", so this is left to URL(string:) as a plain
        // (schemeless) url rather than misread as a relative path.
        let bookmark = Bookmark(id: 0, title: "Example", url: "example.com")
        XCTAssertFalse(bookmark.isLocalPath)
    }
}

final class BookmarkCSVTests: XCTestCase {
    func testEmptyInputParsesToNoBookmarks() {
        XCTAssertEqual(BookmarkCSV.parse(""), [])
        XCTAssertEqual(BookmarkCSV.parse("   \n  \n"), [])
    }

    func testHeaderOnlyParsesToNoBookmarks() {
        XCTAssertEqual(BookmarkCSV.parse("title,url\n"), [])
        XCTAssertEqual(BookmarkCSV.parse("Title,URL"), []) // case-insensitive
    }

    func testHeaderPlusRowsSkipsOnlyTheHeader() {
        let bookmarks = BookmarkCSV.parse("title,url\nHacker News,https://news.ycombinator.com\n")
        XCTAssertEqual(bookmarks, [Bookmark(id: 0, title: "Hacker News", url: "https://news.ycombinator.com")])
    }

    func testBareRowsWithNoHeaderAllParse() {
        let bookmarks = BookmarkCSV.parse("Hacker News,https://news.ycombinator.com\nlobste.rs,https://lobste.rs")
        XCTAssertEqual(bookmarks.map(\.title), ["Hacker News", "lobste.rs"])
        XCTAssertEqual(bookmarks.map(\.id), [0, 1])
    }

    func testBlankLinesInterspersedAreSkipped() {
        let bookmarks = BookmarkCSV.parse("""
        Hacker News,https://news.ycombinator.com

        lobste.rs,https://lobste.rs

        """)
        XCTAssertEqual(bookmarks.map(\.title), ["Hacker News", "lobste.rs"])
    }

    func testQuotedTitleContainingACommaParses() {
        let bookmarks = BookmarkCSV.parse(#""Foo, Bar",https://example.com"#)
        XCTAssertEqual(bookmarks, [Bookmark(id: 0, title: "Foo, Bar", url: "https://example.com")])
    }

    func testQuotedTitleWithAnEscapedQuoteParses() {
        let bookmarks = BookmarkCSV.parse(#""Say ""Hi""",https://example.com"#)
        XCTAssertEqual(bookmarks, [Bookmark(id: 0, title: #"Say "Hi""#, url: "https://example.com")])
    }

    func testMalformedRowWithNoCommaIsSkipped() {
        let bookmarks = BookmarkCSV.parse("just some text\nHacker News,https://news.ycombinator.com")
        XCTAssertEqual(bookmarks.map(\.title), ["Hacker News"])
    }

    func testRowWithEmptyURLIsSkipped() {
        let bookmarks = BookmarkCSV.parse("No URL,\nHacker News,https://news.ycombinator.com")
        XCTAssertEqual(bookmarks.map(\.title), ["Hacker News"])
    }

    func testRowWithEmptyTitleIsSkipped() {
        let bookmarks = BookmarkCSV.parse(",https://example.com\nHacker News,https://news.ycombinator.com")
        XCTAssertEqual(bookmarks.map(\.title), ["Hacker News"])
    }

    func testCRLFLineEndingsParse() {
        let bookmarks = BookmarkCSV.parse("Hacker News,https://news.ycombinator.com\r\nlobste.rs,https://lobste.rs\r\n")
        XCTAssertEqual(bookmarks.map(\.title), ["Hacker News", "lobste.rs"])
    }

    func testIdsAreSequentialAndSkipMalformedRows() {
        let bookmarks = BookmarkCSV.parse("""
        title,url
        Hacker News,https://news.ycombinator.com
        not a bookmark
        lobste.rs,https://lobste.rs
        """)
        XCTAssertEqual(bookmarks.map(\.id), [0, 1])
        XCTAssertEqual(bookmarks.map(\.title), ["Hacker News", "lobste.rs"])
    }

    func testUnquotedCommaInTheURLIsKeptWithTheURL() {
        let bookmarks = BookmarkCSV.parse("Maps,https://maps.example.com?ids=1,2,3")
        XCTAssertEqual(bookmarks, [Bookmark(id: 0, title: "Maps", url: "https://maps.example.com?ids=1,2,3")])
    }
}

final class BookmarkFilterTests: XCTestCase {
    private func bookmarks() -> [Bookmark] {
        [
            Bookmark(id: 0, title: "Hacker News", url: "https://news.ycombinator.com"),
            Bookmark(id: 1, title: "GitHub", url: "https://github.com"),
            Bookmark(id: 2, title: "lobste.rs", url: "https://lobste.rs")
        ]
    }

    func testEmptyQueryReturnsEverythingInOrder() {
        XCTAssertEqual(BookmarkFilter.filter(bookmarks(), query: "").map(\.id), [0, 1, 2])
    }

    func testFilterMatchesByTitleSubsequence() {
        let ids = BookmarkFilter.filter(bookmarks(), query: "hn").map(\.id)
        XCTAssertEqual(ids, [0])
    }

    func testQueryMatchingOnlyTheURLStillMatches() {
        // "ycombinator" is only in the url, not the title, so it should still
        // surface the bookmark rather than being excluded entirely.
        let ids = BookmarkFilter.filter(bookmarks(), query: "ycombinator").map(\.id)
        XCTAssertEqual(ids, [0])
    }

    func testTitleMatchesRankAboveURLOnlyMatches() {
        let bookmarks = [
            Bookmark(id: 0, title: "Cool Site", url: "https://example.com/hn-mirror"),
            Bookmark(id: 1, title: "Hacker News", url: "https://news.ycombinator.com")
        ]
        // "hn" is only a url substring on bookmark 0 (in the path) but a
        // direct title match on bookmark 1 — the title match must win even
        // though it appears later in the file.
        let ids = BookmarkFilter.filter(bookmarks, query: "hn").map(\.id)
        XCTAssertEqual(ids, [1, 0])
    }

    func testTiesPreserveFileOrder() {
        let ids = BookmarkFilter.filter(bookmarks(), query: "").map(\.id)
        XCTAssertEqual(ids, [0, 1, 2])
    }
}
