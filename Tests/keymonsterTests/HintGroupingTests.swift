import CoreGraphics
import XCTest
@testable import keymonster

final class HintGroupingTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let badgeSize = CGSize(width: 22, height: 18)

    private func group(_ anchors: [CGRect]) -> [HintGrouping.Group] {
        HintGrouping.groups(badgeSize: badgeSize, anchors: anchors, within: bounds)
    }

    /// A run of adjacent same-line characters, the text-jump crowding case.
    private func characterRun(_ count: Int) -> [CGRect] {
        (0..<count).map { CGRect(x: 100 + CGFloat($0) * 8, y: 300, width: 8, height: 14) }
    }

    func testLoneTargetGetsItsOwnBadgeAtItsCorner() {
        let anchor = CGRect(x: 100, y: 300, width: 8, height: 14)
        let groups = group([anchor])
        XCTAssertEqual(groups.count, 1)
        XCTAssertFalse(groups[0].isCluster)
        XCTAssertEqual(groups[0].members, [0])
        // The badge hangs above the target's top-left corner, leaving room for
        // the caret pointer between them.
        XCTAssertEqual(groups[0].badge.minX, anchor.minX, accuracy: 0.01)
        XCTAssertEqual(
            groups[0].badge.maxY, anchor.minY - HintGeometry.caretHeight, accuracy: 0.01
        )
    }

    func testFarApartTargetsStayUngrouped() {
        let anchors = [
            CGRect(x: 100, y: 100, width: 8, height: 14),
            CGRect(x: 400, y: 300, width: 8, height: 14)
        ]
        let groups = group(anchors)
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { !$0.isCluster })
    }

    func testCrowdedRunCollapsesIntoOneCluster() {
        let anchors = characterRun(6)
        let groups = group(anchors)
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].isCluster)
        XCTAssertEqual(groups[0].members, Array(0..<6))
        // The area spans the whole run and the badge hangs off its corner.
        let union = anchors.dropFirst().reduce(anchors[0]) { $0.union($1) }
        XCTAssertEqual(groups[0].area, union)
        XCTAssertEqual(groups[0].badge.minX, union.minX, accuracy: 0.01)
    }

    func testGroupingIsTransitive() {
        // a collides with b, b with c — one cluster of three even though a and
        // c never touch directly.
        let anchors = characterRun(3)
        let groups = group(anchors)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].members, [0, 1, 2])
    }

    func testSeparateCrowdsBecomeSeparateClusters() {
        let anchors = characterRun(3) + characterRun(3).map { $0.offsetBy(dx: 300, dy: 0) }
        let groups = group(anchors)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].members, [0, 1, 2])
        XCTAssertEqual(groups[1].members, [3, 4, 5])
    }

    func testNestedElementsWithSeparatedCornersGetSeparateBadges() {
        // Corner-anchored badges of a card and the button at its center hang at
        // different corners, so they stay individually labeled — no cluster.
        let card = CGRect(x: 100, y: 100, width: 300, height: 200)
        let button = CGRect(x: 220, y: 180, width: 80, height: 40)
        let groups = group([card, button])
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { !$0.isCluster })
    }

    func testElementsSharingACornerClusterUp() {
        // Nearly the same top-left corner: both badges want their natural spot
        // and land on top of each other — real crowding, so the pair collapses
        // into one green area label rather than badges escaping sideways.
        let outer = CGRect(x: 100, y: 100, width: 200, height: 120)
        let inner = CGRect(x: 104, y: 103, width: 60, height: 24)
        let groups = group([outer, inner])
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].isCluster)
    }

    func testTopCornerNeighborsEscapeInsteadOfClustering() {
        // A help "?" and a close X stacked in a window's top-right corner: the
        // help badge flips below (no room above), landing right where the close
        // badge hangs. There's clear space around them, so both keep individual
        // labels instead of merging into a cluster.
        let help = CGRect(x: 770, y: 6, width: 17, height: 17)
        let close = CGRect(x: 760, y: 50, width: 17, height: 17)
        let groups = group([help, close])
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { !$0.isCluster })
        XCTAssertFalse(groups[0].badge.insetBy(dx: -1, dy: -1).intersects(groups[1].badge))
        // The escaped badge found genuinely clear space: no badge covers
        // either element.
        for grp in groups {
            for anchor in [help, close] {
                XCTAssertFalse(grp.badge.intersects(anchor), "\(grp.badge) covers \(anchor)")
            }
        }
    }

    func testFinalBadgesNeverCollide() {
        // A tight grid of targets: whatever grouping falls out, the visible
        // badges must all stand clear of each other.
        let anchors = (0..<4).flatMap { row in
            (0..<5).map { column in
                CGRect(x: 100 + CGFloat(column) * 14, y: 100 + CGFloat(row) * 10, width: 10, height: 8)
            }
        }
        let groups = group(anchors)
        for (index, one) in groups.enumerated() {
            for other in groups[(index + 1)...] {
                XCTAssertFalse(
                    one.badge.intersects(other.badge),
                    "\(one.badge) overlaps \(other.badge)"
                )
            }
        }
        // And every target is accounted for exactly once.
        XCTAssertEqual(groups.flatMap(\.members).sorted(), Array(anchors.indices))
    }

    func testBadgesStayInsideBoundsEvenAtTheCorner() {
        let anchors = (0..<8).map { CGRect(x: CGFloat($0) * 6, y: 0, width: 8, height: 14) }
        for grp in group(anchors) {
            XCTAssertTrue(bounds.contains(grp.badge), "\(grp.badge) escapes bounds")
        }
    }

    func testGroupsWithLabelsMatchCounts() {
        let (groups, labels) = HintGrouping.groupsWithLabels(
            anchors: characterRun(6) + [CGRect(x: 500, y: 100, width: 8, height: 14)],
            within: bounds,
            badgeSize: { _ in self.badgeSize }
        )
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(labels.count, 2)
        XCTAssertEqual(Set(labels).count, 2)
    }
}

final class HintZoomTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let badgeSize = CGSize(width: 22, height: 18)

    private func layout(area: CGRect, members: [CGRect]) -> HintZoom.Layout {
        HintZoom.layout(area: area, members: members, badgeSize: badgeSize, bounds: bounds)
    }

    func testPanelStaysInsideBoundsAndMagnifies() {
        let area = CGRect(x: 90, y: 290, width: 70, height: 30)
        let members = (0..<6).map { CGRect(x: 100 + CGFloat($0) * 8, y: 300, width: 8, height: 14) }
        let result = layout(area: area, members: members)
        XCTAssertTrue(bounds.contains(result.panel))
        XCTAssertGreaterThanOrEqual(result.scale, 2)
        XCTAssertTrue(result.panel.contains(result.canvas))
    }

    func testContentPreservesTheMembersArrangement() {
        let area = CGRect(x: 90, y: 290, width: 70, height: 30)
        let members = (0..<3).map { CGRect(x: 100 + CGFloat($0) * 20, y: 300, width: 8, height: 14) }
        let result = layout(area: area, members: members)
        for (member, content) in zip(members, result.content) {
            XCTAssertEqual(
                content.minX,
                result.canvas.minX + (member.minX - area.minX) * result.scale,
                accuracy: 0.01
            )
            XCTAssertEqual(content.width, member.width * result.scale, accuracy: 0.01)
        }
    }

    func testZoomBadgesNeverOverlapEvenWhenConcentric() {
        // Two members sharing a center can't be separated by any scale; their
        // labels must still come out readable.
        let area = CGRect(x: 100, y: 100, width: 120, height: 80)
        let members = [
            CGRect(x: 100, y: 100, width: 120, height: 80),
            CGRect(x: 140, y: 125, width: 40, height: 30)
        ]
        let result = layout(area: area, members: members)
        XCTAssertFalse(result.badges[0].intersects(result.badges[1]))
        for badge in result.badges {
            XCTAssertTrue(result.panel.contains(badge), "\(badge) escapes the panel")
        }
    }

    func testCloseCharactersSpreadApartAtZoomScale() {
        // Characters 8pt apart at 1x must end up at least a badge apart.
        let area = CGRect(x: 92, y: 292, width: 40, height: 30)
        let members = (0..<3).map { CGRect(x: 100 + CGFloat($0) * 8, y: 300, width: 8, height: 14) }
        let result = layout(area: area, members: members)
        for (index, one) in result.badges.enumerated() {
            for other in result.badges[(index + 1)...] {
                XCTAssertFalse(one.intersects(other))
            }
        }
    }
}
