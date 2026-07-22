import XCTest
@testable import keymonster

@MainActor
final class UpdateCheckerTests: XCTestCase {
    // MARK: - Version comparison

    func testNewerPatchMinorAndMajorVersions() {
        XCTAssertTrue(UpdateChecker.isNewer("0.1.1", than: "0.1.0"))
        XCTAssertTrue(UpdateChecker.isNewer("0.2.0", than: "0.1.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.0", than: "0.9.9"))
    }

    func testEqualAndOlderVersionsAreNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.1.0", than: "0.1.1"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.9", than: "1.0.0"))
    }

    func testComponentsCompareNumericallyNotLexically() {
        XCTAssertTrue(UpdateChecker.isNewer("0.10.0", than: "0.9.1"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.1", than: "0.10.0"))
    }

    func testMissingComponentsCountAsZero() {
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0"))
    }

    func testNonNumericComponentsNeverLookNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("abc", than: "0.1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.1.beta", than: "0.1.0"))
    }

    func testVersionFromTagStripsLeadingV() {
        XCTAssertEqual(UpdateChecker.version(fromTag: "v0.2.0"), "0.2.0")
        XCTAssertEqual(UpdateChecker.version(fromTag: "0.2.0"), "0.2.0")
    }

    // MARK: - Checking

    private func checker(current: String?, response: String) -> UpdateChecker {
        UpdateChecker(
            currentVersion: current,
            isEnabled: { true },
            fetch: { _ in Data(response.utf8) }
        )
    }

    func testPublishesNewerReleaseVersion() async {
        let checker = checker(current: "0.1.0", response: #"{"tag_name": "v0.2.0"}"#)
        await checker.check()
        XCTAssertEqual(checker.availableVersion, "0.2.0")
    }

    func testStaysQuietWhenRunningTheLatest() async {
        let checker = checker(current: "0.2.0", response: #"{"tag_name": "v0.2.0"}"#)
        await checker.check()
        XCTAssertNil(checker.availableVersion)
    }

    func testFailedFetchKeepsLastKnownAnswer() async {
        var shouldFail = false
        let checker = UpdateChecker(
            currentVersion: "0.1.0",
            isEnabled: { true },
            fetch: { _ in
                if shouldFail { throw URLError(.notConnectedToInternet) }
                return Data(#"{"tag_name": "v0.2.0"}"#.utf8)
            }
        )
        await checker.check()
        shouldFail = true
        await checker.check()
        XCTAssertEqual(checker.availableVersion, "0.2.0")
    }

    func testMalformedResponseKeepsLastKnownAnswer() async {
        var response = #"{"tag_name": "v0.2.0"}"#
        let checker = UpdateChecker(
            currentVersion: "0.1.0",
            isEnabled: { true },
            fetch: { _ in Data(response.utf8) }
        )
        await checker.check()
        response = "not json"
        await checker.check()
        XCTAssertEqual(checker.availableVersion, "0.2.0")
    }

    func testNoBundleVersionMeansNoCheck() async {
        var fetched = false
        let checker = UpdateChecker(
            currentVersion: nil,
            isEnabled: { true },
            fetch: { _ in
                fetched = true
                return Data()
            }
        )
        await checker.check()
        XCTAssertFalse(fetched)
        XCTAssertNil(checker.availableVersion)
    }

    func testOptOutSkipsFetchAndRetractsStaleAnswer() async {
        var enabled = true
        var fetchCount = 0
        let checker = UpdateChecker(
            currentVersion: "0.1.0",
            isEnabled: { enabled },
            fetch: { _ in
                fetchCount += 1
                return Data(#"{"tag_name": "v0.2.0"}"#.utf8)
            }
        )
        await checker.check()
        XCTAssertEqual(checker.availableVersion, "0.2.0")

        enabled = false
        await checker.check()
        XCTAssertNil(checker.availableVersion)
        XCTAssertEqual(fetchCount, 1)
    }

    func testReenablingChecksAgain() async {
        var enabled = false
        let checker = UpdateChecker(
            currentVersion: "0.1.0",
            isEnabled: { enabled },
            fetch: { _ in Data(#"{"tag_name": "v0.2.0"}"#.utf8) }
        )
        await checker.check()
        XCTAssertNil(checker.availableVersion)

        enabled = true
        await checker.check()
        XCTAssertEqual(checker.availableVersion, "0.2.0")
    }

    func testUpdateGoesAwayAfterInstallingIt() async {
        // Simulates relaunching after an update: same feed, newer current.
        let feed = #"{"tag_name": "v0.2.0"}"#
        let stale = checker(current: "0.1.0", response: feed)
        await stale.check()
        XCTAssertEqual(stale.availableVersion, "0.2.0")

        let fresh = checker(current: "0.2.0", response: feed)
        await fresh.check()
        XCTAssertNil(fresh.availableVersion)
    }
}
