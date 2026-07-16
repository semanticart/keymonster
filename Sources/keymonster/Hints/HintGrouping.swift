import CoreGraphics

/// Groups hint targets whose labels would sit too close to read. An isolated
/// target keeps a normal label by its top-left corner; a target whose preferred
/// label spot is taken may escape to clear space beside its element; targets
/// whose labels still collide merge into one group represented by a single
/// green area label. Picking a group's label zooms into its area, where the
/// members get normal labels again.
enum HintGrouping {
    struct Group: Equatable {
        /// Indices into the original target list, ascending.
        let members: [Int]
        /// Union of the members' frames — the area a zoomed view magnifies.
        let area: CGRect
        /// Where the group's one badge is drawn: hanging off `area`'s top-left
        /// corner (or escaped nearby), kept inside `bounds`.
        let badge: CGRect
        /// More than one member: drawn green, and its label opens the zoom.
        var isCluster: Bool { members.count > 1 }
    }

    /// Minimum clear space between badges before they count as colliding.
    private static let gap: CGFloat = 2

    /// Groups `anchors` so no two badges collide. Starts with one group per
    /// anchor, places badges (escaping to free spots where possible), and
    /// repeatedly merges groups whose badges still touch until every badge
    /// stands clear. Groups come out ordered by their first member. `bounds` is
    /// where badges may go — typically the screen, so a badge for an element at
    /// the window's edge can hang just outside the window.
    static func groups(badgeSize: CGSize, anchors: [CGRect], within bounds: CGRect) -> [Group] {
        var members: [[Int]] = anchors.indices.map { [$0] }
        var areas: [CGRect] = anchors
        while true {
            let badges = placedBadges(badgeSize, areas: areas, in: bounds)
            guard let merged = mergingCollisions(members: members, areas: areas, badges: badges)
            else {
                return zip(members, zip(areas, badges)).map {
                    Group(members: $0, area: $1.0, badge: $1.1)
                }
            }
            (members, areas) = merged
        }
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

    /// One badge spot per area. Badges collide for two very different reasons,
    /// treated differently:
    ///
    /// - Real density — badges at their natural spot (above their element)
    ///   overlapping because the elements crowd. These stay put and the caller
    ///   merges them into a cluster.
    /// - Bounds displacement — a badge pushed off its natural spot (flipped
    ///   below at the top edge, clamped sideways at a corner) landing on a
    ///   neighbor's badge the elements' spacing never asked for. These may
    ///   escape to a nearby spot that is free, covers no element, and takes no
    ///   spot another badge prefers; only when no such gap exists do they
    ///   cluster. Displaced badges place last, so they yield to natural ones.
    private static func placedBadges(
        _ size: CGSize, areas: [CGRect], in bounds: CGRect
    ) -> [CGRect] {
        let preferred = areas.map { HintGeometry.badgeRect(size, labeling: $0, in: bounds) }
        let displaced = areas.indices.map { index in
            preferred[index].origin != CGPoint(
                x: areas[index].minX,
                y: areas[index].minY - size.height - HintGeometry.caretHeight
            )
        }
        var placed = preferred
        var taken = areas.indices.compactMap { displaced[$0] ? nil : preferred[$0] }
        for index in areas.indices where displaced[index] {
            let candidates = HintGeometry.badgeCandidates(size, labeling: areas[index], in: bounds)
            let spot = candidates.first { candidate in
                guard isFree(candidate, avoiding: taken) else { return false }
                if candidate == preferred[index] { return true }
                return !areas.indices.contains { other in
                    other != index && (candidate.intersects(areas[other])
                        || candidate.intersects(preferred[other]))
                }
            } ?? preferred[index]
            placed[index] = spot
            taken.append(spot)
        }
        return placed
    }

    private static func isFree(_ candidate: CGRect, avoiding placed: [CGRect]) -> Bool {
        let padded = candidate.insetBy(dx: -gap / 2, dy: -gap / 2)
        return placed.allSatisfy { !padded.intersects($0) }
    }

    /// One merge pass: unions every set of transitively colliding groups, or
    /// returns nil when no badges collide and the layout is done. Each pass
    /// strictly shrinks the group count, so the caller's loop terminates.
    private static func mergingCollisions(
        members: [[Int]], areas: [CGRect], badges: [CGRect]
    ) -> (members: [[Int]], areas: [CGRect])? {
        var component = Array(badges.indices)
        func root(_ index: Int) -> Int {
            var index = index
            while component[index] != index { index = component[index] }
            return index
        }

        var collided = false
        for lhs in badges.indices {
            let padded = badges[lhs].insetBy(dx: -gap / 2, dy: -gap / 2)
            for rhs in badges.indices where rhs > lhs && root(rhs) != root(lhs) {
                if padded.intersects(badges[rhs]) {
                    collided = true
                    component[root(rhs)] = root(lhs)
                }
            }
        }
        guard collided else { return nil }

        var merged: [Int: (members: [Int], area: CGRect)] = [:]
        for index in badges.indices {
            let key = root(index)
            if let existing = merged[key] {
                merged[key] = (existing.members + members[index],
                               existing.area.union(areas[index]))
            } else {
                merged[key] = (members[index], areas[index])
            }
        }
        let groups = merged.values
            .map { (members: $0.members.sorted(), area: $0.area) }
            .sorted { $0.members[0] < $1.members[0] }
        return (groups.map(\.members), groups.map(\.area))
    }
}
