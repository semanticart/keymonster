import XCTest
@testable import keymonster

final class FaviconLinkParserTests: XCTestCase {
    private let pageURL = URL(string: "https://example.com/")!

    func testExtractsHrefFromAnIconLink() {
        let html = #"<head><link rel="icon" href="/favicon.png"></head>"#
        XCTAssertEqual(FaviconLinkParser.iconURL(in: html, pageURL: pageURL),
                        URL(string: "https://example.com/favicon.png"))
    }

    func testExtractsHrefFromAShortcutIconLinkWithSingleQuotes() {
        let html = "<link rel='shortcut icon' href='/icon.ico'>"
        XCTAssertEqual(FaviconLinkParser.iconURL(in: html, pageURL: pageURL),
                        URL(string: "https://example.com/icon.ico"))
    }

    func testAttributeOrderDoesNotMatter() {
        let html = #"<link href="/icon.png" rel="icon">"#
        XCTAssertEqual(FaviconLinkParser.iconURL(in: html, pageURL: pageURL),
                        URL(string: "https://example.com/icon.png"))
    }

    func testMatchingIsCaseInsensitive() {
        let html = #"<LINK REL="ICON" HREF="/icon.png">"#
        XCTAssertEqual(FaviconLinkParser.iconURL(in: html, pageURL: pageURL),
                        URL(string: "https://example.com/icon.png"))
    }

    func testResolvesAnAbsoluteCDNHref() {
        // The real formhealth.co markup: a Webflow site declaring its icon on
        // a completely different host, self-closed, href before rel.
        let html = """
        <link href="https://cdn.prod.website-files.com/abc/favicon.png" rel="shortcut icon" type="image/x-icon"/>
        """
        XCTAssertEqual(FaviconLinkParser.iconURL(in: html, pageURL: pageURL),
                        URL(string: "https://cdn.prod.website-files.com/abc/favicon.png"))
    }

    func testResolvesAProtocolRelativeHref() {
        let html = #"<link rel="icon" href="//cdn.example.com/icon.png">"#
        XCTAssertEqual(FaviconLinkParser.iconURL(in: html, pageURL: pageURL),
                        URL(string: "https://cdn.example.com/icon.png"))
    }

    func testPlainIconWinsOverAppleTouchIconRegardlessOfOrder() {
        let html = """
        <link rel="apple-touch-icon" href="/touch.png">
        <link rel="icon" href="/favicon.png">
        """
        XCTAssertEqual(FaviconLinkParser.iconURL(in: html, pageURL: pageURL),
                        URL(string: "https://example.com/favicon.png"))
    }

    func testFallsBackToAppleTouchIconWhenThatsAllThereIs() {
        let html = #"<link rel="apple-touch-icon" href="/touch.png">"#
        XCTAssertEqual(FaviconLinkParser.iconURL(in: html, pageURL: pageURL),
                        URL(string: "https://example.com/touch.png"))
    }

    func testNoLinkTagReturnsNil() {
        XCTAssertNil(FaviconLinkParser.iconURL(in: "<html><body>Hi</body></html>", pageURL: pageURL))
    }

    func testUnrecognizedRelReturnsNil() {
        let html = #"<link rel="stylesheet" href="/style.css">"#
        XCTAssertNil(FaviconLinkParser.iconURL(in: html, pageURL: pageURL))
    }
}
