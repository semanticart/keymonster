import XCTest
@testable import keymonster

@MainActor
final class ScriptLogTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("keymonster-scriptlog-tests-\(UUID().uuidString)")
            .appendingPathComponent("scripts.log")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        fileURL = nil
        super.tearDown()
    }

    func testRecordPublishesLastFailure() {
        let log = ScriptLog(fileURL: fileURL)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        log.record(script: "backup.sh", detail: "exited 1: disk full", date: date)

        XCTAssertEqual(
            log.lastFailure,
            ScriptLog.Failure(script: "backup.sh", detail: "exited 1: disk full", date: date)
        )
    }

    func testRecordAppendsTimestampedLinesToTheFile() throws {
        let log = ScriptLog(fileURL: fileURL)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        log.record(script: "a.sh", detail: "exited 1", date: date)
        log.record(script: "b.scpt", detail: "failed to launch", date: date)

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(contents, """
        2023-11-14T22:13:20Z a.sh: exited 1
        2023-11-14T22:13:20Z b.scpt: failed to launch

        """)
    }

    func testStartsWithNoFailure() {
        XCTAssertNil(ScriptLog(fileURL: fileURL).lastFailure)
    }
}
