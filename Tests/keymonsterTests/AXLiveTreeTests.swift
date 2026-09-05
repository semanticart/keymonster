import ApplicationServices
import Foundation
import XCTest
@testable import keymonster

/// Drives the real accessibility API against the `axfixture` window, so the
/// live half of text jump — the one the recorded trees in `TextOccurrenceTests`
/// can only imitate — gets exercised too: does an AppKit field really answer
/// per-character bounds, does a WebKit editable really hide its geometry on leaf
/// nodes, does the omnibox shape really come back empty.
///
/// Reading any accessibility tree needs the Accessibility grant, and an
/// untrusted process can't even read its own (the API answers
/// `kAXErrorCannotComplete`). CI can't hold that grant, so these tests skip
/// themselves unless the test runner has it. To run them locally, grant
/// Accessibility to whatever runs `swift test` — your terminal — and then
/// `make axtest`.
final class AXLiveTreeTests: XCTestCase {
    private var fixture: Process?

    override func tearDown() {
        fixture?.terminate()
        fixture = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testNativeFieldAnswersPerCharacterBounds() throws {
        let tree = LiveAXTextTree()
        let app = try launchFixture()
        let field = try XCTUnwrap(
            waitForElement(in: app, withValue: "fixture native field hello", tree: tree),
            "no native NSTextField in the fixture window"
        )
        let hits = find("h", value: "fixture native field hello", element: field, tree: tree)

        // "h" appears in "hello" only — twice would mean the search leaked into
        // a neighbouring field.
        XCTAssertEqual(hits.count, 1)
        let hit = try XCTUnwrap(hits.first)
        XCTAssertFalse(hit.rect.isEmpty, "a native field must answer real geometry")
        guard case .offset = hit.caret else {
            return XCTFail("a native field should take the caret by offset, got \(hit.caret)")
        }
    }

    func testWebContentIsInvisibleUntilAccessibilityIsArmed() throws {
        let tree = LiveAXTextTree()
        let app = try launchFixture(armWebAccessibility: false)
        // Deliberately a single read, not `waitForElement`: the first request
        // for the web view's children is itself what makes WebKit start
        // vending, so a second pass would find the content whether or not
        // anything armed it. What this pins down is what a one-shot reader
        // sees — nothing — which is the symptom text jump had.
        XCTAssertNil(
            element(in: app, withValue: "fixture web editable hello", tree: tree),
            "a WKWebView vends no tree until an assistive client asks — the reason "
                + "AXFocusedText.focused() arms it, and the reason text jump used to see "
                + "web fields only in apps hint mode had already visited"
        )
    }

    func testWebEditableResolvesOnceArmed() throws {
        let tree = LiveAXTextTree()
        let app = try launchFixture()
        let editable = try XCTUnwrap(
            waitForElement(in: app, withValue: "fixture web editable hello", tree: tree),
            "no contenteditable in the fixture's WKWebView"
        )
        let hits = find("h", value: "fixture web editable hello", element: editable, tree: tree)
        XCTAssertFalse(hits.isEmpty)
        for hit in hits {
            XCTAssertFalse(hit.rect.isEmpty)
        }

        // WebKit answers real bounds on the editable container, so this resolves
        // through the *native* path even though it is web content. Chromium is
        // the one that answers junk there and forces the leaf path — which is
        // exactly why no fixture can stand in for it, and why Slack's shape
        // lives as a recorded tree in TextOccurrenceTests instead.
        guard case .offset = try XCTUnwrap(hits.first).caret else {
            return XCTFail("WebKit containers answer bounds, so the caret should be an offset")
        }
    }

    func testOmniboxShapeFindsNothing() throws {
        let tree = LiveAXTextTree()
        let app = try launchFixture()
        let omnibox = try XCTUnwrap(
            waitForElement(in: app, withValue: "https://fixture.example.com/path?query=hello", tree: tree),
            "no omnibox mimic in the fixture window"
        )
        let hits = find(
            "q", value: "https://fixture.example.com/path?query=hello", element: omnibox, tree: tree
        )

        // Same known gap the recorded Chrome tree documents, reproduced against
        // a live AX server: no per-character geometry and no leaves means
        // nowhere to put a badge.
        XCTAssertTrue(hits.isEmpty)
    }

    // MARK: - Harness

    private func find(
        _ character: Character, value: String, element: AXUIElement, tree: LiveAXTextTree
    ) -> [TextOccurrence] {
        TextSearch(
            tree: tree, window: .infinite,
            budget: TextSearchBudget(maxOccurrences: 100, maxLeafNodes: 4000, hasTimeLeft: { true })
        ).find(character, in: value, element: element)
    }

    /// Starts the fixture and returns its application element, once its window
    /// and web content are up. Skips the whole test when the runner is
    /// untrusted, since every AX read below would fail for that reason alone.
    private func launchFixture(armWebAccessibility: Bool = true) throws -> AXUIElement {
        try XCTSkipUnless(
            AXIsProcessTrusted(),
            "needs Accessibility for the test runner; see this file's doc comment"
        )
        let binary = productsDirectory.appendingPathComponent("axfixture")
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: binary.path),
            "axfixture not built; run `swift build` first"
        )

        let process = Process()
        process.executableURL = binary
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        fixture = process

        try waitForReady(on: output)
        let app = AXUIElementCreateApplication(process.processIdentifier)
        if armWebAccessibility {
            // What AXFocusedText.focused() does before reading, and without
            // which the WKWebView's content simply isn't in the tree.
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            Thread.sleep(forTimeInterval: 1.0)
        }
        return app
    }

    /// Blocks until the fixture prints its ready line, so the web view has
    /// finished loading and is vending accessibility.
    private func waitForReady(on pipe: Pipe) throws {
        let ready = expectation(description: "fixture ready")
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        DispatchQueue.global().async {
            var seen = ""
            var buffer = [UInt8](repeating: 0, count: 4096)
            while !seen.contains("fixture ready") {
                let count = read(descriptor, &buffer, buffer.count)
                guard count > 0 else { break } // the fixture exited
                seen += String(bytes: buffer[0..<count], encoding: .utf8) ?? ""
            }
            if seen.contains("fixture ready") { ready.fulfill() }
        }
        wait(for: [ready], timeout: 30)
        // The AX server lags the first paint by a frame or two.
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// `element(in:withValue:)`, retried until it answers or `timeout` runs out.
    ///
    /// WebKit vends its accessibility tree lazily: the web view's group is
    /// empty until an assistive client first asks for its children, and the
    /// web content process takes well under a second after that ask to fill
    /// it in. A single walk therefore sees nothing on the first pass no matter
    /// how long it waited beforehand, so the lookup has to be the thing that
    /// asks and then come back.
    private func waitForElement(
        in root: AXUIElement, withValue value: String, tree: LiveAXTextTree,
        timeout: TimeInterval = 5
    ) -> AXUIElement? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while true {
            if let found = element(in: root, withValue: value, tree: tree) { return found }
            guard Date() < deadline else { return nil }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Depth-first search of the fixture's tree for the element carrying `value`.
    private func element(
        in root: AXUIElement, withValue value: String, tree: LiveAXTextTree, limit: Int = 4000
    ) -> AXUIElement? {
        var stack = [root]
        var visited = 0
        while let node = stack.popLast(), visited < limit {
            visited += 1
            if tree.stringValue(of: node)?.trimmingCharacters(in: .whitespacesAndNewlines) == value {
                return node
            }
            stack.append(contentsOf: tree.children(of: node).reversed())
        }
        return nil
    }

    /// Where SwiftPM put the built binaries for this test run.
    private var productsDirectory: URL {
        Bundle.allBundles
            .first { $0.bundlePath.hasSuffix(".xctest") }?
            .bundleURL.deletingLastPathComponent()
            ?? URL(fileURLWithPath: ".build/debug")
    }
}
