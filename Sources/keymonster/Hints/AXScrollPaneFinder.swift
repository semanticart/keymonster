import AppKit
import ApplicationServices
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints.scroll")

/// A scrollable pane found in the focused window: the element scroll mode
/// aims at plus its frame in AX (global, top-left origin) coordinates.
struct ScrollPane {
    let element: AXUIElement
    var frame: CGRect
}

/// Which panes deserve a badge. Pure so the rules are testable without a
/// live accessibility tree.
enum ScrollPaneFilter {
    /// Roles that conventionally scroll. `AXScrollArea` is the native answer,
    /// but Electron apps (Slack) expose no scroll areas at all — their content
    /// root is an `AXWebArea` and their side panes are bare outlines and
    /// lists — so those container roles count as panes too. Scrolling posts
    /// wheel events at the pane's center, which works regardless of which
    /// element actually owns the scrolling.
    static let paneRoles: Set<String> = [
        kAXScrollAreaRole as String,
        "AXWebArea",
        kAXOutlineRole as String,
        kAXListRole as String,
        kAXTableRole as String,
        kAXTextAreaRole as String
    ]

    /// Panes whose visible portion is thinner than this in either direction
    /// aren't worth scrolling — there's nowhere for a badge and barely any
    /// content behind it.
    static let minSide: CGFloat = 40

    static func isUsable(visible: CGRect) -> Bool {
        visible.width >= minSide && visible.height >= minSide
    }

    /// Whether a pane can scroll vertically, from the best evidence on hand.
    /// A native scroll bar's enabled state is authoritative — AppKit disables
    /// the scroller exactly when the content fits, so it overrules geometry
    /// in both directions (an empty text view fills its viewport and would
    /// pass the geometry test; a horizontal-only scroll area might fail it).
    /// With no scroll bar to consult — web panes expose none — the content
    /// geometry decides.
    static func isScrollable(barEnabled: Bool?, content: CGRect, pane: CGRect) -> Bool {
        barEnabled ?? hasScrollableContent(content, pane: pane)
    }

    /// Whether a pane's laid-out content could plausibly scroll vertically:
    /// it reaches (or overflows) the pane's vertical extent. Virtualized
    /// lists — web and native alike — only materialize on-screen rows, so
    /// fullness is the strongest static signal there is; Chromium exposes no
    /// "scrollable" state at all. A pane whose content stops well short of
    /// its bottom edge has nothing to scroll — a channel sidebar with a
    /// handful of channels — and offering it as a pane would be a dead pick.
    ///
    /// `content` is the union of the pane's children's frames (scroll bars
    /// excluded — they span the viewport whether or not anything scrolls). A
    /// null union means the children were unmeasurable, and the pane gets the
    /// benefit of the doubt.
    static func hasScrollableContent(_ content: CGRect, pane: CGRect) -> Bool {
        guard !content.isNull, !content.isEmpty, !pane.isEmpty else { return true }
        let topGap = max(0, content.minY - pane.minY)
        let bottomGap = max(0, pane.maxY - content.maxY)
        return topGap + bottomGap <= restingGapAllowance
    }

    /// How much unfilled viewport still counts as full — a list scrolled to
    /// its top often rests with its last row a row-height shy of the bottom
    /// edge without that meaning it can't scroll.
    static let restingGapAllowance: CGFloat = 40

    /// Whether a candidate nested inside another candidate is really the same
    /// scroller seen twice — a native outline filling the scroll area that
    /// scrolls it — as opposed to a genuinely distinct sub-pane, like Slack's
    /// channel sidebar occupying a sliver of the web area. Same scroller:
    /// suppress the inner one; distinct: badge both.
    static func isRedundant(visible: CGRect, withinAncestor ancestor: CGRect) -> Bool {
        let overlap = visible.intersection(ancestor)
        guard !overlap.isEmpty, !ancestor.isEmpty else { return false }
        let coverage = (overlap.width * overlap.height) / (ancestor.width * ancestor.height)
        return coverage >= 0.8
    }
}

/// Walks the accessibility tree of the frontmost app's focused window and
/// returns every visible scrollable pane, so scroll mode can outline and
/// drive them. Same bounded breadth-first walk as `AXHintTargetFinder`, whose
/// plumbing it borrows.
@MainActor
enum AXScrollPaneFinder {
    struct Scan {
        let panes: [ScrollPane]
        /// Focused window frame in AX (global, top-left origin) coordinates.
        let windowFrame: CGRect
    }

    private static let maxElements = 3000
    private static let timeBudget: TimeInterval = 0.5

    /// Scans the frontmost app, or `app` when given — the escape hatch the
    /// debug `scrollscan` command uses to exercise this exact code path
    /// against an app that isn't frontmost.
    static func scan(of chosenApp: NSRunningApplication? = nil) -> Scan? {
        guard let app = chosenApp ?? NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        // Same ask as the other finders: browsers only grow an accessibility
        // tree for web content once an assistive client requests it.
        AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        guard let window = AXHintTargetFinder.focusedWindow(of: axApp),
              let windowFrame = AXHintTargetFinder.frame(of: window) else {
            log.info("no focused window for \(app.bundleIdentifier ?? "?")")
            return nil
        }

        let start = Date()
        var panes: [ScrollPane] = []
        var seenFrames: Set<String> = []
        // Each entry remembers the visible rect of its nearest pane ancestor,
        // so a nested candidate can be recognized as the same scroller seen
        // twice (see `ScrollPaneFilter.isRedundant`).
        var queue: [(element: AXUIElement, paneAbove: CGRect?)] = [(window, nil)]
        var head = 0

        while head < queue.count, head < maxElements, Date().timeIntervalSince(start) < timeBudget {
            let (element, paneAbove) = queue[head]
            head += 1

            let values = AXHintTargetFinder.attributes(of: element, [
                kAXRoleAttribute as String,
                kAXPositionAttribute as String,
                kAXSizeAttribute as String,
                kAXChildrenAttribute as String
            ])
            let read = Read(
                role: values[0] as? String,
                frame: AXHintTargetFinder.frame(position: values[1], size: values[2]),
                children: AXHintTargetFinder.children(from: values[3])
            )

            let vetted = vet(
                element, read: read, windowFrame: windowFrame,
                paneAbove: paneAbove, seenFrames: &seenFrames
            )
            if let pane = vetted?.pane { panes.append(pane) }

            // Skip subtrees that are provably outside the window; recurse into
            // everything else, including elements that report no frame at all.
            if let frame = read.frame, !frame.isEmpty, !frame.intersects(windowFrame) {
                continue
            }
            for child in read.children {
                queue.append((child, vetted?.visible ?? paneAbove))
            }
        }

        log.debug("scanned \(head) elements, found \(panes.count) scroll pane(s)")
        return Scan(panes: panes, windowFrame: windowFrame)
    }

    /// One element's attributes, fetched in a single IPC round trip.
    private struct Read {
        let role: String?
        let frame: CGRect?
        let children: [AXUIElement]
    }

    /// Vets one element as a pane candidate. nil means it wasn't a serious
    /// candidate at all; otherwise `visible` is the rect its descendants
    /// should treat as their nearest pane ancestor — set even when `pane` is
    /// nil, so an unscrollable scroll area's verdict extends to the document
    /// view filling it (an empty text view would otherwise re-qualify on the
    /// benefit of the doubt: it has no children to measure).
    private static func vet(
        _ element: AXUIElement, read: Read, windowFrame: CGRect, paneAbove: CGRect?,
        seenFrames: inout Set<String>
    ) -> (pane: ScrollPane?, visible: CGRect)? {
        guard let role = read.role, ScrollPaneFilter.paneRoles.contains(role),
              let elementFrame = read.frame else {
            return nil
        }
        let visible = elementFrame.intersection(windowFrame)
        // `isUsable` also guards the key below: an off-window pane's
        // intersection is the null rect, whose infinite origin can't become
        // an Int.
        guard ScrollPaneFilter.isUsable(visible: visible),
              paneAbove.map({ !ScrollPaneFilter.isRedundant(visible: visible, withinAncestor: $0) })
                  ?? true else {
            return nil
        }
        // Nested wrappers can report pixel-identical frames; one badge per
        // distinct rectangle is enough. The scrollability check goes last:
        // it's the only test costing extra AX round trips.
        let key = "\(Int(visible.minX)),\(Int(visible.minY)),\(Int(visible.width)),\(Int(visible.height))"
        guard !seenFrames.contains(key),
              ScrollPaneFilter.isScrollable(
                  barEnabled: verticalScrollBarEnabled(of: element),
                  content: contentUnion(of: read.children), pane: elementFrame
              )
        else {
            return (nil, visible)
        }
        seenFrames.insert(key)
        return (ScrollPane(element: element, frame: elementFrame), visible)
    }

    /// The pane's vertical scroll bar's enabled state, or nil when there is
    /// no scroll bar to ask (web panes, overlay-scroller setups that don't
    /// expose one).
    private static func verticalScrollBarEnabled(of element: AXUIElement) -> Bool? {
        guard let bar = AXHintTargetFinder.element(
            of: element, attribute: kAXVerticalScrollBarAttribute as String
        ) else {
            return nil
        }
        let values = AXHintTargetFinder.attributes(of: bar, [kAXEnabledAttribute as String])
        return (values[0] as? NSNumber)?.boolValue
    }

    /// The union of the children's frames — how far the pane's materialized
    /// content actually reaches. Scroll bars are skipped: they hug the
    /// viewport's full height whether or not anything can move.
    private static func contentUnion(of children: [AXUIElement]) -> CGRect {
        var union = CGRect.null
        for child in children {
            let values = AXHintTargetFinder.attributes(of: child, [
                kAXRoleAttribute as String,
                kAXPositionAttribute as String,
                kAXSizeAttribute as String
            ])
            if values[0] as? String == kAXScrollBarRole as String { continue }
            if let frame = AXHintTargetFinder.frame(position: values[1], size: values[2]),
               !frame.isEmpty {
                union = union.union(frame)
            }
        }
        return union
    }

    /// The pane's current frame, re-read from the live tree — nil once the
    /// element has left the screen (its view was torn down or the window
    /// closed), which tells scroll mode to stand down.
    static func currentFrame(of pane: ScrollPane) -> CGRect? {
        AXHintTargetFinder.frame(of: pane.element)
    }
}
