import XCTest
@testable import keymonster

final class ApplicationsProviderTests: XCTestCase {
    private func makeDirs() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = root.appendingPathComponent("a"), second = root.appendingPathComponent("b")
        for dir in [first, second] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (first, second)
    }

    private func makeApp(_ name: String, in dir: URL) throws {
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("\(name).app"), withIntermediateDirectories: true
        )
    }

    func testScanFindsAppsOnlyAndDedupesByNameKeepingTheFirstDirectory() throws {
        let (first, second) = try makeDirs()
        try makeApp("Safari", in: first)
        try makeApp("Safari", in: second)
        try makeApp("Notes", in: second)
        try Data().write(to: first.appendingPathComponent("readme.txt"))
        let apps = ApplicationsProvider.scan([first, second])
        XCTAssertEqual(apps.map(\.name), ["Safari", "Notes"])
        XCTAssertTrue(apps.first?.path.hasSuffix("/a/Safari.app") == true)
    }

    func testScanToleratesAMissingDirectory() {
        XCTAssertTrue(ApplicationsProvider.scan([URL(fileURLWithPath: "/nonexistent-\(UUID())")]).isEmpty)
    }

    func testSuggestionsFuzzyMatchTheNameAndOpenThePath() {
        let provider = ApplicationsProvider(apps: [("Safari", "/Applications/Safari.app"), ("Notes", "/n/Notes.app")])
        let rows = provider.suggestions(for: "saf")
        XCTAssertEqual(rows.map(\.title), ["Safari"])
        XCTAssertEqual(rows.first?.url, "/Applications/Safari.app")
        XCTAssertTrue(provider.suggestions(for: "zzz").isEmpty)
    }

    func testSuggestionsAreCapped() {
        let apps = (0..<20).map { (name: "App\($0)", path: "/A/App\($0).app") }
        XCTAssertEqual(ApplicationsProvider(apps: apps).suggestions(for: "app").count, ApplicationsProvider.maxResults)
    }
}
