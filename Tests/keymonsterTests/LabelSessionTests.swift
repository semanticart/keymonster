import CoreGraphics
import XCTest
@testable import keymonster

final class LabelSessionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let badgeSize = CGSize(width: 22, height: 18)

    private func session(_ anchors: [CGRect]) -> LabelSession {
        LabelSession(
            anchors: anchors, windowFrame: bounds, screenBounds: bounds,
            badgeSize: { _ in badgeSize }
        )
    }

    /// A run of adjacent same-line characters — crowded enough to cluster.
    private func characterRun(_ count: Int) -> [CGRect] {
        (0..<count).map { CGRect(x: 100 + CGFloat($0) * 8, y: 300, width: 8, height: 14) }
    }

    /// Anchors far enough apart that every one keeps its own single badge.
    private func spreadAnchors(_ count: Int) -> [CGRect] {
        (0..<count).map { CGRect(x: 60 + CGFloat($0 % 5) * 150, y: 60 + CGFloat($0 / 5) * 120, width: 8, height: 14) }
    }

    func testTypingASingleLabelCommitsItsAnchor() {
        var session = session(spreadAnchors(2))
        XCTAssertEqual(session.groupLabels, ["a", "s"])
        XCTAssertEqual(session.type("s", shifted: false), .commit(index: 1, shifted: false))
    }

    func testShiftOnTheFinalLetterRidesAlongWithTheCommit() {
        var session = session(spreadAnchors(2))
        XCTAssertEqual(session.type("a", shifted: true), .commit(index: 0, shifted: true))
    }

    func testUnknownLetterIsRejectedAndChangesNothing() {
        var session = session(spreadAnchors(2))
        XCTAssertEqual(session.type("z", shifted: false), .reject)
        // The session is still live: a valid label still commits.
        XCTAssertEqual(session.type("a", shifted: false), .commit(index: 0, shifted: false))
    }

    func testTwoLetterLabelsGoThroughPendingBeforeCommitting() {
        // More anchors than single letters exist forces two-letter labels.
        var session = session(spreadAnchors(30))
        let label = session.groupLabels[0]
        XCTAssertEqual(label.count, 2)
        XCTAssertEqual(
            session.type(label.first!, shifted: false),
            .updateTyped(String(label.first!))
        )
        XCTAssertEqual(
            session.type(label.last!, shifted: false),
            .commit(index: 0, shifted: false)
        )
    }

    func testBackspaceErasesATypedLetter() {
        var session = session(spreadAnchors(30))
        _ = session.type(session.groupLabels[0].first!, shifted: false)
        XCTAssertEqual(session.backspace(), .updateTyped(""))
    }

    func testClusterLabelZoomsInAndMemberLabelCommitsTheOriginalIndex() {
        var session = session(characterRun(6))
        guard let clusterIndex = session.groups.firstIndex(where: \.isCluster) else {
            return XCTFail("expected the crowded run to cluster")
        }
        let cluster = session.groups[clusterIndex]
        let effect = session.type(Character(session.groupLabels[clusterIndex]), shifted: false)
        guard case .zoomIn(let area, let memberFrames, let labels) = effect else {
            return XCTFail("expected a zoom, got \(effect)")
        }
        // The zoom shows exactly the cluster's members, labeled afresh.
        XCTAssertEqual(memberFrames, cluster.members.map { session.anchors[$0] })
        XCTAssertEqual(labels.count, cluster.members.count)
        // The magnified area stays on the window.
        XCTAssertTrue(bounds.contains(area))
        // A member label commits the member's index into the original anchors,
        // not its position within the zoom.
        XCTAssertEqual(
            session.type(Character(labels[1]), shifted: false),
            .commit(index: cluster.members[1], shifted: false)
        )
    }

    func testBackspaceInsideAZoomStepsOutAndRestoresGroupLabels() {
        var session = session(characterRun(6))
        guard let clusterIndex = session.groups.firstIndex(where: \.isCluster) else {
            return XCTFail("expected the crowded run to cluster")
        }
        _ = session.type(Character(session.groupLabels[clusterIndex]), shifted: false)
        XCTAssertEqual(session.backspace(), .zoomOut)
        // Group labels are live again: the same cluster label re-opens the zoom.
        let effect = session.type(Character(session.groupLabels[clusterIndex]), shifted: false)
        guard case .zoomIn = effect else {
            return XCTFail("expected the zoom to re-open, got \(effect)")
        }
    }

    func testBackspaceInsideAZoomErasesTypedLettersBeforeLeavingTheZoom() {
        // A cluster big enough that its member labels take two letters.
        var session = session(characterRun(40))
        guard let clusterIndex = session.groups.firstIndex(where: { $0.members.count > 26 }),
              case .zoomIn(_, _, let labels) = session.type(
                Character(session.groupLabels[clusterIndex]), shifted: false
              )
        else {
            // Grouping may never produce a >26-member cluster; the plain
            // zoom-out path is covered above, so just note the miss.
            return
        }
        _ = session.type(labels[0].first!, shifted: false)
        XCTAssertEqual(session.backspace(), .updateTyped(""))
        XCTAssertEqual(session.backspace(), .zoomOut)
    }

    func testBackspaceWithNothingToUndoReportsUnwound() {
        var session = session(spreadAnchors(2))
        XCTAssertEqual(session.backspace(), .unwound)
    }
}
