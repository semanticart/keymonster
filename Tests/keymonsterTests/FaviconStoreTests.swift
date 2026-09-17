import AppKit
import XCTest
@testable import keymonster

@MainActor
final class FaviconStoreTests: XCTestCase {
    /// A minimal valid 1x1 transparent PNG, decodable by `NSImage`.
    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keymonster-favicon-test-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testHostOfExtractsAndLowercasesTheHost() {
        XCTAssertEqual(FaviconStore.host(of: "https://News.YCombinator.com/item?id=1"), "news.ycombinator.com")
        XCTAssertNil(FaviconStore.host(of: "not a url"))
    }

    func testRequestFetchesAndPublishesTheFavicon() async {
        var requestedURLs: [URL] = []
        let store = FaviconStore(cacheDirectory: directory) { url in
            requestedURLs.append(url)
            return Self.onePixelPNG
        }

        await store.request(for: "https://example.com/page")

        XCTAssertEqual(requestedURLs, [URL(string: "https://example.com/favicon.ico")!])
        XCTAssertNotNil(store.images["example.com"])
    }

    func testRequestWritesToDiskAndASecondInstanceLoadsFromCache() async {
        let store = FaviconStore(cacheDirectory: directory) { _ in Self.onePixelPNG }
        await store.request(for: "https://example.com")
        XCTAssertNotNil(store.images["example.com"])

        var fetchCount = 0
        let reloaded = FaviconStore(cacheDirectory: directory) { _ in
            fetchCount += 1
            return Self.onePixelPNG
        }
        await reloaded.request(for: "https://example.com")

        XCTAssertNotNil(reloaded.images["example.com"])
        XCTAssertEqual(fetchCount, 0, "a disk-cached favicon should not trigger a network fetch")
    }

    func testRequestForAnAlreadyCachedHostDoesNotRefetch() async {
        var fetchCount = 0
        let store = FaviconStore(cacheDirectory: directory) { _ in
            fetchCount += 1
            return Self.onePixelPNG
        }
        await store.request(for: "https://example.com")
        await store.request(for: "https://example.com")

        XCTAssertEqual(fetchCount, 1)
    }

    func testFailedFetchLeavesNoFaviconAndDoesNotCrash() async {
        let store = FaviconStore(cacheDirectory: directory) { _ in nil }
        await store.request(for: "https://example.com")

        XCTAssertNil(store.images["example.com"])
    }

    func testUnparseableURLIsANoOp() async {
        let store = FaviconStore(cacheDirectory: directory) { _ in
            XCTFail("should never fetch for an unparseable url")
            return nil
        }
        await store.request(for: "not a url")

        XCTAssertTrue(store.images.isEmpty)
    }

    // MARK: - HTML <link rel="icon"> fallback

    func testFallsBackToTheHomepagesDeclaredIconWhenFaviconICOIsMissing() async {
        var requestedURLs: [URL] = []
        let html = #"<link rel="icon" href="/assets/icon.png">"#
        let store = FaviconStore(cacheDirectory: directory) { url in
            requestedURLs.append(url)
            switch url {
            case URL(string: "https://example.com/favicon.ico")!: return nil
            case URL(string: "https://example.com/")!: return html.data(using: .utf8)
            case URL(string: "https://example.com/assets/icon.png")!: return Self.onePixelPNG
            default: return nil
            }
        }

        await store.request(for: "https://example.com/page")

        XCTAssertEqual(requestedURLs, [
            URL(string: "https://example.com/favicon.ico")!,
            URL(string: "https://example.com/")!,
            URL(string: "https://example.com/assets/icon.png")!
        ])
        XCTAssertNotNil(store.images["example.com"])
    }

    func testFallsBackToAnAbsoluteCDNIconDeclaredOnTheHomepage() async {
        // Mirrors formhealth.co: a Webflow-built site whose icon lives on a
        // different host entirely, only discoverable via the <link> tag.
        let cdnIcon = "https://cdn.example-cdn.com/abc/favicon.png"
        let html = #"<link href="\#(cdnIcon)" rel="shortcut icon" type="image/x-icon"/>"#
        let store = FaviconStore(cacheDirectory: directory) { url in
            switch url.absoluteString {
            case "https://example.com/favicon.ico": return nil
            case "https://example.com/": return html.data(using: .utf8)
            case cdnIcon: return Self.onePixelPNG
            default: return nil
            }
        }

        await store.request(for: "https://example.com")

        XCTAssertNotNil(store.images["example.com"])
    }

    func testGivesUpWhenNeitherFaviconICONorAnyDeclaredIconWorks() async {
        let store = FaviconStore(cacheDirectory: directory) { url in
            url == URL(string: "https://example.com/")! ? Data("<html></html>".utf8) : nil
        }

        await store.request(for: "https://example.com")

        XCTAssertNil(store.images["example.com"])
    }

    func testGivesUpWhenTheHomepageFetchAlsoFails() async {
        let store = FaviconStore(cacheDirectory: directory) { _ in nil }

        await store.request(for: "https://example.com")

        XCTAssertNil(store.images["example.com"])
    }
}
