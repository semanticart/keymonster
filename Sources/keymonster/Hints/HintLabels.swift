import Foundation

/// Generates the two-letter labels shown over clickable elements in hint mode.
/// Pure logic, kept apart from the AX/overlay machinery so it can be unit tested.
enum HintLabels {
    /// Letters grouped by typing comfort. Earlier rows are cheaper to reach, so
    /// pairs drawn entirely from the home row are handed out first.
    static let rows = ["asdfghjkl", "qwertyuiop", "zxcvbnm"]

    /// The largest number of distinct two-letter labels we can produce (26²).
    static var maxCount: Int {
        let letters = rows.reduce(0) { $0 + $1.count }
        return letters * letters
    }

    /// `count` distinct labels, cheapest-to-type first. When they all fit in
    /// single letters (26 or fewer), each label is one keystroke — home row
    /// first, so a handful of targets resolve with a single press. Beyond that
    /// they're two-letter pairs, home-row-only pairs first, then pairs mixing in
    /// the top row, then the bottom. All labels are the same length, so no label
    /// is a prefix of another and matching stays unambiguous.
    static func labels(count: Int) -> [String] {
        guard count > 0 else { return [] }
        let weighted: [(letter: Character, weight: Int)] = rows.enumerated().flatMap { row, letters in
            letters.map { ($0, row) }
        }

        // Few enough to name with one keystroke each.
        if count <= weighted.count {
            return weighted.sorted { $0.weight < $1.weight }
                .prefix(count)
                .map { String($0.letter) }
        }

        var pairs: [(label: String, weight: Int)] = []
        for first in weighted {
            for second in weighted {
                pairs.append((String([first.letter, second.letter]), first.weight + second.weight))
            }
        }
        // Stable sort: within a weight tier, pairs keep their generation order.
        return pairs.sorted { $0.weight < $1.weight }
            .prefix(count)
            .map(\.label)
    }
}

/// Tracks the letters typed while hints are showing and decides when they
/// uniquely identify a target. Labels are all the same length, so no label is a
/// prefix of another and matching is unambiguous.
struct HintSelection {
    let labels: [String]
    private(set) var typed: String = ""

    enum Outcome: Equatable {
        /// More letters needed; `matches` labels still start with what's typed.
        case pending(matches: Int)
        /// The typed letters exactly name one label.
        case matched(index: Int)
        /// No label starts with the attempted prefix; the keystroke is ignored.
        case rejected
    }

    mutating func type(_ letter: Character) -> Outcome {
        let candidate = typed + String(letter)
        if let index = labels.firstIndex(of: candidate) {
            typed = ""
            return .matched(index: index)
        }
        let matches = labels.lazy.filter { $0.hasPrefix(candidate) }.count
        guard matches > 0 else { return .rejected }
        typed = candidate
        return .pending(matches: matches)
    }

    mutating func backspace() {
        typed = String(typed.dropLast())
    }
}
