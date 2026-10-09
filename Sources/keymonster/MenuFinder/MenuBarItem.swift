import Foundation

/// One actionable leaf in an app's menu bar — e.g. the "Save As…" item nested
/// under "File". Pure and AppKit-free so the fuzzy matcher and view model can be
/// tested without walking a live accessibility tree; the scanner keeps the
/// matching `AXUIElement` in a side table keyed by `id`.
struct MenuBarItem: Identifiable, Equatable {
    let id: Int
    /// Ancestor menu titles from the top-level menu down to (but excluding) the
    /// item itself, e.g. `["File", "Export"]`.
    let path: [String]
    /// The leaf item's own title, e.g. `"PDF…"`.
    let title: String

    /// Breadcrumb shown in the list, e.g. `"File › Export › PDF…"`.
    var breadcrumb: String { (path + [title]).joined(separator: " › ") }

    /// The string fuzzy matching runs against: the whole path plus the title,
    /// space-joined, so typing `"exp pdf"` reaches `File › Export › PDF…`.
    var searchString: String { (path + [title]).joined(separator: " ") }
}

/// Subsequence fuzzy matching with light scoring. A query matches a candidate
/// when its characters appear in order (not necessarily adjacent); the score
/// rewards matches that are consecutive or land on word boundaries, so the
/// closest item floats to the top and Return runs it.
enum FuzzyMatch {
    /// Returns a score (higher is better) if every query character appears in
    /// `candidate` in order, or nil if it isn't a subsequence at all. An empty
    /// query scores 0 (everything matches).
    static func score(_ candidate: String, query: String) -> Int? {
        let cand = Array(candidate.lowercased())
        let needle = Array(query.lowercased())
        guard !needle.isEmpty else { return 0 }

        var score = 0
        var consecutive = 0
        var lastMatch = -1
        var matched = 0

        for (index, char) in cand.enumerated() where matched < needle.count {
            guard char == needle[matched] else { continue }
            score += 1
            if lastMatch == index - 1 {
                consecutive += 1
                score += consecutive * 5 // runs of adjacent hits are what we want
            } else {
                consecutive = 0
            }
            if index == 0 || isBoundary(cand[index - 1]) {
                score += 10 // matching the start of a word (e.g. an initial)
            }
            lastMatch = index
            matched += 1
        }

        return matched == needle.count ? score : nil
    }

    /// Multi-word scoring: every whitespace-separated word of `query` must
    /// match `candidate` on its own, in any order, so "pr co" finds both
    /// "core prs" and "prod core". Words that start a word in the candidate
    /// (and especially the candidate itself) score higher, and the words
    /// appearing in the order they were typed earns a bonus. A single-word
    /// query scores exactly like `score`.
    static func scoreWords(_ candidate: String, query: String) -> Int? {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count <= 1 { return score(candidate, query: words.first ?? "") }

        let cand = candidate.lowercased()
        var total = 0
        var positions: [Int] = []
        for word in words {
            guard let wordScore = score(candidate, query: word) else { return nil }
            let lowered = word.lowercased()
            total += wordScore
            if let start = wordPrefixOffset(cand, prefix: lowered) {
                total += start == 0 ? 30 : 15
                positions.append(start)
            } else {
                let first = cand.firstIndex(of: lowered.first!)
                positions.append(first.map { cand.distance(from: cand.startIndex, to: $0) } ?? 0)
            }
        }
        if zip(positions, positions.dropFirst()).allSatisfy({ $0 < $1 }) { total += 25 }
        return total
    }

    /// Character offset of the first word in `text` that starts with `prefix`.
    private static func wordPrefixOffset(_ text: String, prefix: String) -> Int? {
        let chars = Array(text)
        let needle = Array(prefix)
        guard !needle.isEmpty, chars.count >= needle.count else { return nil }
        for start in 0...(chars.count - needle.count) where start == 0 || isBoundary(chars[start - 1]) {
            if Array(chars[start..<start + needle.count]) == needle { return start }
        }
        return nil
    }

    private static func isBoundary(_ char: Character) -> Bool {
        char == " " || char == "›"
    }
}

/// Ranks menu items against a query. Pure so ordering is exercised in tests.
enum MenuItemFilter {
    /// The items that match `query`, best match first; the full list in menu
    /// order when the query is empty. Ties keep their original order (stable).
    static func filter(_ items: [MenuBarItem], query: String) -> [MenuBarItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }

        // Carry the original index so ties keep menu order (a stable sort).
        struct Scored { let item: MenuBarItem; let score: Int; let index: Int }
        return items.enumerated()
            .compactMap { index, item -> Scored? in
                guard let score = FuzzyMatch.scoreWords(item.searchString, query: trimmed) else { return nil }
                return Scored(item: item, score: score, index: index)
            }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .map(\.item)
    }
}
