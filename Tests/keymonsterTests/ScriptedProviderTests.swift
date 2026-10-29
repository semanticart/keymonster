import XCTest
@testable import keymonster

final class ScriptedProviderTests: XCTestCase {
    private let uuidScript = """
    function suggest(q) {
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(q)) return []
      return [
        { title: "Order " + q, url: "https://admin.example.com/orders/" + q },
        { title: "Logs for " + q, url: "https://logs.example.com/?q=" + q }
      ]
    }
    """
    private let uuid = "123e4567-e89b-12d3-a456-426614174000"

    func testReturnsSeveralSuggestionsForAMatchingQuery() throws {
        let provider = try ScriptedProvider(name: "uuid.js", source: uuidScript)
        let results = provider.suggestions(for: uuid)
        XCTAssertEqual(results.map(\.title), ["Order \(uuid)", "Logs for \(uuid)"])
        XCTAssertEqual(results.first?.url, "https://admin.example.com/orders/\(uuid)")
    }

    func testReturnsNothingForANonMatchingQuery() throws {
        let provider = try ScriptedProvider(name: "uuid.js", source: uuidScript)
        XCTAssertEqual(provider.suggestions(for: "hacker news"), [])
    }

    func testSkipsMalformedItemsAndTolerantOfUndefined() throws {
        let provider = try ScriptedProvider(name: "x.js", source: """
        function suggest(q) {
          if (q === "none") return
          return [{ title: "ok", url: "https://a.b" }, { title: "no url" }, { url: "https://no.title" }, 7]
        }
        """)
        XCTAssertEqual(provider.suggestions(for: "none"), [])
        XCTAssertEqual(provider.suggestions(for: "x").map(\.title), ["ok"])
    }

    func testAThrowingScriptContributesNothingAndRecordsTheError() throws {
        let provider = try ScriptedProvider(
            name: "boom.js", source: "function suggest(q) {\n  throw new Error('boom')\n}"
        )
        XCTAssertEqual(provider.suggestions(for: "x"), [])
        XCTAssertEqual(provider.lastError, "Error: boom (line 2)")
    }

    func testANonArrayResultIsAnError() throws {
        let provider = try ScriptedProvider(name: "obj.js", source: "function suggest(q) { return { title: 'a' } }")
        XCTAssertEqual(provider.suggestions(for: "x"), [])
        XCTAssertEqual(provider.lastError, "suggest must return an array of {title, url}")
    }

    func testTheErrorClearsOnceTheScriptSucceedsAgain() throws {
        let provider = try ScriptedProvider(
            name: "flaky.js", source: "function suggest(q) { if (q === 'bad') throw new Error('x'); return [] }"
        )
        _ = provider.suggestions(for: "bad")
        XCTAssertNotNil(provider.lastError)
        _ = provider.suggestions(for: "good")
        XCTAssertNil(provider.lastError)
    }

    func testRejectsSourceThatDoesNotLoadOrLacksSuggest() {
        XCTAssertThrowsError(try ScriptedProvider(name: "syntax.js", source: "function (")) { error in
            XCTAssertTrue("\(error)".contains("SyntaxError"), "\(error)")
        }
        XCTAssertThrowsError(try ScriptedProvider(name: "nosuggest.js", source: "var x = 1")) { error in
            XCTAssertEqual("\(error)", "does not define a suggest(query) function")
        }
        let source = "\n\nthrow new Error('at load')"
        XCTAssertThrowsError(try ScriptedProvider(name: "throws.js", source: source)) { error in
            XCTAssertEqual("\(error)", "Error: at load (line 3)")
        }
    }

    func testStoreLoadsJSFilesInNameOrderAndSkipsBrokenOnes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keymonster-providers-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try uuidScript.write(to: dir.appendingPathComponent("b.js"), atomically: true, encoding: .utf8)
        try "function suggest(q){return []}"
            .write(to: dir.appendingPathComponent("a.js"), atomically: true, encoding: .utf8)
        try "function (".write(to: dir.appendingPathComponent("c.js"), atomically: true, encoding: .utf8)
        try "ignored".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        var failures: [String] = []
        let loaded = ProviderStore.load(from: dir) { name, _ in failures.append(name) }
        XCTAssertEqual(loaded.map(\.name), ["a.js", "b.js"])
        XCTAssertEqual(failures, ["c.js"])
        XCTAssertEqual(ProviderStore.load(from: dir.appendingPathComponent("missing")).count, 0)
    }

    @MainActor
    func testFinderPutsProviderRowsAboveBookmarksAndSelectsTheFirst() throws {
        let provider = try ScriptedProvider(name: "uuid.js", source: uuidScript)
        let model = BookmarksFinderViewModel()
        model.present(
            bookmarks: [Bookmark(id: 0, title: "Hacker News", url: "https://news.ycombinator.com")],
            providers: [provider]
        )
        model.searchText = uuid
        XCTAssertEqual(model.filteredBookmarks.map(\.title), ["Order \(uuid)", "Logs for \(uuid)"])
        XCTAssertEqual(model.activateSelection()?.url, "https://admin.example.com/orders/\(uuid)")

        model.searchText = "hacker"
        XCTAssertEqual(model.filteredBookmarks.map(\.title), ["Hacker News"])
    }
}

final class ProviderInstructionsTests: XCTestCase {
    func testTheExampleScriptLoadsAndRuns() throws {
        let provider = try ScriptedProvider(name: "uuid.js", source: ProviderInstructions.exampleScript)
        let uuid = "123e4567-e89b-12d3-a456-426614174000"
        XCTAssertEqual(provider.suggestions(for: uuid).count, 2)
        XCTAssertEqual(provider.suggestions(for: "hacker news"), [])
    }

    func testInstructionsNameTheFolderAndEmbedTheExample() {
        let directory = URL(fileURLWithPath: "/tmp/providers")
        let text = ProviderInstructions.text(directory: directory)
        XCTAssertTrue(text.contains("/tmp/providers/<name>.js"))
        XCTAssertTrue(text.contains("function suggest(query)"))
        XCTAssertTrue(text.contains(ProviderInstructions.exampleScript))
    }
}
