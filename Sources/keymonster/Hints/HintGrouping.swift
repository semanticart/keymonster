import CoreGraphics

/// Groups hint targets whose labels would sit too close to read. An isolated
/// target keeps a normal label by its top-left corner; targets whose labels
/// would collide merge into one group represented by a single green area
/// label. Picking a group's label zooms into its area, where the members get
/// normal labels again.
enum HintGrouping {
    struct Group: Equatable {
        /// Indices into the original target list, ascending.
        let members: [Int]
        /// Union of the members' frames — the area a zoomed view magnifies.
        let area: CGRect
        /// Where the group's one badge is drawn: hanging off `area`'s top-left
        /// corner, kept inside the window.
        let badge: CGRect
        /// More than one member: drawn green, and its label opens the zoom.
        var isCluster: Bool { members.count > 1 }
    }

    /// Minimum clear space between badges before they count as colliding.
    private static let gap: CGFloat = 2

    /// Groups `anchors` so no two badges collide. Starts with one group per
    /// anchor and repeatedly merges groups whose badges (all `badgeSize`,
    /// centered on each group's area, kept inside `bounds`) still touch, until
    /// every badge stands clear. Groups come out ordered by their first member.
    static func groups(badgeSize: CGSize, anchors: [CGRect], within bounds: CGRect) -> [Group] {
        var groups = anchors.enumerated().map { index, anchor in
            Group(members: [index], area: anchor, badge: badge(badgeSize, on: anchor, in: bounds))
        }
        while let merged = mergingCollisions(in: groups, badgeSize: badgeSize, bounds: bounds) {
            groups = merged
        }
        return groups
    }

    /// Groups plus their labels. Label length depends on how many labels are
    /// needed, and badge width depends on label length, so when grouping
    /// changes the length (say 30 targets collapse into a dozen groups), the
    /// grouping is redone at the right size.
    static func groupsWithLabels(
        anchors: [CGRect], within bounds: CGRect, badgeSize: (Int) -> CGSize
    ) -> (groups: [Group], labels: [String]) {
        let guessed = HintLabels.labelLength(for: anchors.count)
        var result = groups(badgeSize: badgeSize(guessed), anchors: anchors, within: bounds)
        let actual = HintLabels.labelLength(for: result.count)
        if actual != guessed {
            result = groups(badgeSize: badgeSize(actual), anchors: anchors, within: bounds)
        }
        return (result, HintLabels.labels(count: result.count))
    }

    /// One merge pass: unions every set of transitively colliding groups, or
    /// returns nil when no badges collide and the layout is done. Each pass
    /// strictly shrinks the group count, so the caller's loop terminates.
    private static func mergingCollisions(
        in groups: [Group], badgeSize: CGSize, bounds: CGRect
    ) -> [Group]? {
        var component = Array(groups.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while component[index] != index { index = component[index] }
            return index
        }

        var collided = false
        for lhs in groups.indices {
            let padded = groups[lhs].badge.insetBy(dx: -gap / 2, dy: -gap / 2)
            for rhs in groups.indices where rhs > lhs && root(rhs) != root(lhs) {
                if padded.intersects(groups[rhs].badge) {
                    collided = true
                    component[root(rhs)] = root(lhs)
                }
            }
        }
        guard collided else { return nil }

        var merged: [Int: (members: [Int], area: CGRect)] = [:]
        for (index, group) in groups.enumerated() {
            let key = root(index)
            if let existing = merged[key] {
                merged[key] = (existing.members + group.members, existing.area.union(group.area))
            } else {
                merged[key] = (group.members, group.area)
            }
        }
        return merged.values
            .map { Group(members: $0.members.sorted(), area: $0.area,
                         badge: badge(badgeSize, on: $0.area, in: bounds)) }
            .sorted { $0.members[0] < $1.members[0] }
    }

    private static func badge(_ size: CGSize, on area: CGRect, in bounds: CGRect) -> CGRect {
        HintGeometry.badgeRect(size, labeling: area, in: bounds)
    }
}
