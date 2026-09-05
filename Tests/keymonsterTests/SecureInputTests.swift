import XCTest
@testable import keymonster

/// The attribution logic behind the Secure Keyboard Entry banner and window.
/// `kCGSSessionSecureInputPID` names the app *receiving* secure input (the
/// frontmost one), not the process that enabled it, so we only blame a holder
/// when it's a distinct background process. These cases pin that rule down.
@MainActor
final class SecureInputTests: XCTestCase {
    private func snapshot(
        enabled: Bool = true,
        holderPID: Int? = nil,
        holderName: String? = nil,
        frontmostPID: pid_t? = nil,
        screenLocked: Bool = false
    ) -> SecureInput.Snapshot {
        SecureInput.Snapshot(
            enabled: enabled, holderPID: holderPID, holderName: holderName, holderBundleID: nil,
            frontmostPID: frontmostPID, frontmostName: nil, screenLocked: screenLocked
        )
    }

    func testFreeInputBlamesNoOne() {
        XCTAssertNil(snapshot(enabled: false, holderPID: 42, holderName: "Slack").attributableHolderName)
    }

    func testHolderEqualToFrontmostIsNotBlamed() {
        // The misleading case: reported holder is just the frontmost app.
        let snap = snapshot(holderPID: 100, holderName: "Google Chrome", frontmostPID: 100)
        XCTAssertTrue(snap.holderIsFrontmost)
        XCTAssertNil(snap.attributableHolderName)
    }

    func testDistinctBackgroundHolderIsBlamed() {
        let snap = snapshot(holderPID: 200, holderName: "Music", frontmostPID: 100)
        XCTAssertFalse(snap.holderIsFrontmost)
        XCTAssertEqual(snap.attributableHolderName, "Music")
    }

    func testLockedScreenIsNotBlamed() {
        // While locked the pid is masked as loginwindow — never a real culprit.
        let snap = snapshot(holderPID: 300, holderName: "loginwindow", frontmostPID: 100, screenLocked: true)
        XCTAssertNil(snap.attributableHolderName)
    }

    func testUnknownHolderIsNotBlamed() {
        XCTAssertNil(snapshot(holderPID: nil, holderName: nil, frontmostPID: 100).attributableHolderName)
    }

    func testDescribeFlagsFrontmostAsUnreliable() {
        let snap = snapshot(holderPID: 100, holderName: "Slack", frontmostPID: 100)
        XCTAssertTrue(SecureInputMonitor.describe(snap).contains("unreliable"))
    }

    func testDescribeFlagsBackgroundHolder() {
        let snap = snapshot(holderPID: 200, holderName: "Music", frontmostPID: 100)
        XCTAssertTrue(SecureInputMonitor.describe(snap).contains("background"))
    }

}
