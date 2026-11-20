import ApplicationServices
import XCTest
@testable import keymonster

final class ScrollDomainRuleTests: XCTestCase {
    func testNormalizeAcceptsDomainsAndURLs() {
        XCTAssertEqual(ScrollDomainRule.normalize("GitHub.com"), "github.com")
        XCTAssertEqual(ScrollDomainRule.normalize(" https://www.github.com/foo/bar "), "github.com")
        XCTAssertNil(ScrollDomainRule.normalize("  "))
        XCTAssertNil(ScrollDomainRule.normalize("nodots"))
    }

    func testRuleForPageURL() {
        XCTAssertEqual(ScrollDomainRule.rule(for: URL(string: "https://www.github.com/a/b")), "github.com")
        XCTAssertNil(ScrollDomainRule.rule(for: nil))
        XCTAssertNil(ScrollDomainRule.rule(for: URL(string: "file:///tmp/x.html")))
    }

    func testMatchesCoversSubdomainsOnly() {
        XCTAssertTrue(ScrollDomainRule.matches(host: "github.com", rules: ["github.com"]))
        XCTAssertTrue(ScrollDomainRule.matches(host: "gist.github.com", rules: ["github.com"]))
        XCTAssertFalse(ScrollDomainRule.matches(host: "notgithub.com", rules: ["github.com"]))
        XCTAssertFalse(ScrollDomainRule.matches(host: "github.com", rules: []))
    }

    func testResolvePicksBiggestPaneForListedHost() throws {
        let window = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let element = AXUIElementCreateSystemWide()
        let small = ScrollPane(element: element, frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let big = ScrollPane(element: element, frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        let url = URL(string: "https://github.com/a/b")
        let rules = ["github.com"]

        let picked = ScrollDomainRule.resolve(panes: [small, big], pageURL: url, rules: rules, windowFrame: window)
        XCTAssertEqual(picked.map(\.frame), [big.frame])

        let other = URL(string: "https://example.com")
        XCTAssertEqual(
            ScrollDomainRule.resolve(panes: [small, big], pageURL: other, rules: rules, windowFrame: window).count, 2
        )
        XCTAssertEqual(
            ScrollDomainRule.resolve(panes: [small, big], pageURL: nil, rules: rules, windowFrame: window).count, 2
        )
    }

    func testBiggestIsMeasuredWithinTheWindow() {
        let window = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let element = AXUIElementCreateSystemWide()
        let hanging = ScrollPane(element: element, frame: CGRect(x: 0, y: 0, width: 100, height: 5000))
        let main = ScrollPane(element: element, frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        XCTAssertEqual(ScrollDomainRule.largest(of: [hanging, main], in: window)?.frame, main.frame)
    }
}
