import CoreGraphics

/// One labeling round, shared by hint mode and text jump: anchor rects are
/// grouped into badges, typed letters narrow the labels, a matched cluster
/// label zooms into its group, and a matched single label commits an anchor.
/// Pure state and transitions — the controllers translate the returned
/// effects into overlay, click, and caret side effects, which keeps every
/// zoom/selection rule here testable without a screen.
struct LabelSession {
    /// What the caller should do in response to a keystroke.
    enum Effect: Equatable {
        /// The typed prefix changed; redraw the badge dimming.
        case updateTyped(String)
        /// A cluster label matched: magnify `area` and label the members.
        case zoomIn(area: CGRect, memberFrames: [CGRect], labels: [String])
        /// Left the zoom; the group badges are current again.
        case zoomOut
        /// A full label matched: act on `anchors[index]`.
        case commit(index: Int, shifted: Bool)
        /// The keystroke names no label; ignore it (with a beep).
        case reject
        /// Backspace with nothing typed and no zoom to leave — the session has
        /// nothing left to unwind, so the mode decides (hint mode stays put,
        /// text jump returns to its character pick).
        case unwound
    }

    /// The rects being labeled, in AX coordinates. `Effect.commit` indexes
    /// into this array.
    let anchors: [CGRect]

    private let windowFrame: CGRect
    private(set) var groups: [HintGrouping.Group]
    private(set) var groupLabels: [String]
    private(set) var zoomed: HintGrouping.Group?
    private var selection: HintSelection

    /// `screenBounds` is where badges may go (the window's screen, so edge
    /// labels can hang outside the window); zoom areas stay clipped to
    /// `windowFrame` itself.
    init(
        anchors: [CGRect],
        windowFrame: CGRect,
        screenBounds: CGRect,
        badgeSize: (Int) -> CGSize
    ) {
        self.anchors = anchors
        self.windowFrame = windowFrame
        (groups, groupLabels) = HintGrouping.groupsWithLabels(
            anchors: anchors, within: screenBounds, badgeSize: badgeSize
        )
        selection = HintSelection(labels: groupLabels)
    }

    mutating func type(_ letter: Character, shifted: Bool) -> Effect {
        switch selection.type(letter) {
        case .matched(let index):
            return picked(index, shifted: shifted)
        case .pending:
            return .updateTyped(selection.typed)
        case .rejected:
            return .reject
        }
    }

    /// Erases the last typed letter, or steps out of the zoom once nothing is
    /// typed, or reports `.unwound` when there's nothing left to step out of.
    mutating func backspace() -> Effect {
        if !selection.typed.isEmpty {
            selection.backspace()
            return .updateTyped(selection.typed)
        }
        if zoomed != nil {
            zoomed = nil
            selection = HintSelection(labels: groupLabels)
            return .zoomOut
        }
        return .unwound
    }

    /// A full label was typed: inside the zoom it names a member; outside it
    /// names a group, which either commits (single) or zooms in (cluster).
    private mutating func picked(_ index: Int, shifted: Bool) -> Effect {
        if let zoomed {
            return .commit(index: zoomed.members[index], shifted: shifted)
        }
        let group = groups[index]
        guard group.isCluster else {
            return .commit(index: group.members[0], shifted: shifted)
        }
        zoomed = group
        let memberFrames = group.members.map { anchors[$0] }
        let labels = HintLabels.labels(count: memberFrames.count)
        selection = HintSelection(labels: labels)
        // A little context around the members, kept on the window.
        let area = group.area.insetBy(dx: -8, dy: -8).intersection(windowFrame)
        return .zoomIn(area: area, memberFrames: memberFrames, labels: labels)
    }
}
