import CoreGraphics
import Foundation

/// Per-site scroll preference for browsers. Sites like GitHub nest half a
/// dozen scrollers, so the pane pick turns into a wall of overlapping badges;
/// for domains the user lists, scroll mode skips the pick and aims at the
/// biggest pane instead. Pure so the rules are testable without a live
/// accessibility tree.
enum ScrollDomainRule {
    /// The host a user typed — a bare domain or a pasted URL — reduced to the
    /// lowercase form rules are stored in. nil when nothing host-like is left.
    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard var host = URL(string: candidate)?.host, host.contains(".") || host == "localhost" else {
            return nil
        }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// The rule that would cover the page at `url`, or nil for non-web pages.
    static func rule(for url: URL?) -> String? {
        url?.host.flatMap(normalize)
    }

    /// A rule for `github.com` covers `gist.github.com` too, but not
    /// `notgithub.com`.
    static func matches(host: String, rules: [String]) -> Bool {
        let host = host.lowercased()
        return rules.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The pane covering the most of the window, ties going to the earlier
    /// (outer) one.
    static func largest(of panes: [ScrollPane], in windowFrame: CGRect) -> ScrollPane? {
        func area(_ pane: ScrollPane) -> CGFloat {
            let visible = pane.frame.intersection(windowFrame)
            return visible.isNull ? 0 : visible.width * visible.height
        }
        var best: ScrollPane?
        for pane in panes where best.map({ area(pane) > area($0) }) ?? true {
            best = pane
        }
        return best
    }

    /// The panes scroll mode should offer: just the biggest one when the
    /// page's host is in `rules`, otherwise all of them.
    static func resolve(
        panes: [ScrollPane], pageURL: URL?, rules: [String], windowFrame: CGRect
    ) -> [ScrollPane] {
        guard panes.count > 1, let host = pageURL?.host,
              matches(host: host, rules: rules),
              let biggest = largest(of: panes, in: windowFrame) else {
            return panes
        }
        return [biggest]
    }
}
