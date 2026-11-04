import CoreGraphics
import XCTest
@testable import keymonster

final class AdaptiveBadgeAlignmentTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
    private let badgeSize = CGSize(width: 22, height: 18)

    func testAdaptiveBadgeCentersOnSmallTargetsAndHangsOffWideOnes() {
        let icon = CGRect(x: 200, y: 300, width: 24, height: 24)
        let field = CGRect(x: 200, y: 400, width: 300, height: 30)
        let iconBadge = HintGeometry.badgeRect(badgeSize, labeling: icon, in: bounds, alignment: .adaptive)
        let fieldBadge = HintGeometry.badgeRect(badgeSize, labeling: field, in: bounds, alignment: .adaptive)
        XCTAssertEqual(iconBadge.midX, icon.midX)
        XCTAssertEqual(fieldBadge.minX, field.minX)
        // The cutoff is a multiple of the badge's own width.
        let edge = badgeSize.width * HintGeometry.BadgeAlignment.smallTargetBadgeWidths
        let atEdge = CGRect(x: 200, y: 300, width: edge, height: 20)
        let pastEdge = CGRect(x: 200, y: 300, width: edge + 1, height: 20)
        XCTAssertEqual(HintGeometry.BadgeAlignment.adaptive.x(labeling: atEdge, width: badgeSize.width),
                       atEdge.midX - badgeSize.width / 2)
        XCTAssertEqual(HintGeometry.BadgeAlignment.adaptive.x(labeling: pastEdge, width: badgeSize.width),
                       pastEdge.minX)
    }

    func testAdaptiveGroupingMixesAlignmentsInOneSession() {
        let icon = CGRect(x: 100, y: 300, width: 24, height: 24)
        let field = CGRect(x: 400, y: 300, width: 300, height: 30)
        let groups = HintGrouping.groups(
            badgeSize: badgeSize, anchors: [icon, field], within: bounds, alignment: .adaptive
        )
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].badge.midX, icon.midX)
        XCTAssertEqual(groups[1].badge.minX, field.minX)
    }
}
