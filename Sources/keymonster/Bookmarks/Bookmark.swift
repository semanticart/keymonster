import Foundation

/// One bookmark: a title and a URL, read from a line of the bookmarks CSV file
/// (see `BookmarksStore`). Pure and AppKit-free so parsing and ranking are
/// unit-tested without touching disk. `id` is a 0-based index assigned in file
/// order at parse time — the list is reparsed fresh every time the finder panel
/// opens, so identity only needs to be stable within one presentation, not
/// across edits of the hand-maintained file.
struct Bookmark: Identifiable, Equatable {
    let id: Int
    let title: String
    let url: String
}

/// Parses the bookmarks CSV file: one `title,url` per line, with minimal
/// RFC4180-style quoting so a title containing a comma can be written
/// `"Foo, Bar",https://example.com`. Malformed or incomplete lines are skipped
/// rather than surfaced as an error — a bad row in a hand-edited file shouldn't
/// take down the rest of the list.
enum BookmarkCSV {
    /// Parses `text` into bookmarks, in file order. A first line that
    /// case-insensitively reads `title,url` is treated as a header and dropped;
    /// blank lines are skipped; a line with no usable comma, or an empty title
    /// or URL after trimming, is skipped.
    static func parse(_ text: String) -> [Bookmark] {
        var lines = text.split(whereSeparator: \.isNewline).map(String.init)
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces).lowercased() == "title,url" {
            lines.removeFirst()
        }

        var bookmarks: [Bookmark] = []
        for line in lines {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let (title, url) = parseLine(line) else { continue }
            bookmarks.append(Bookmark(id: bookmarks.count, title: title, url: url))
        }
        return bookmarks
    }

    /// Splits one line into its title and url fields, or nil if either is
    /// empty after trimming. A field wrapped in double quotes may contain
    /// commas and newlines-within-quotes are not supported (bookmarks are
    /// always one line); `""` inside a quoted field is an escaped quote.
    private static func parseLine(_ line: String) -> (title: String, url: String)? {
        let chars = Array(line)
        var fields: [String] = []
        var current = ""
        var index = 0
        var inQuotes = false

        while index < chars.count {
            let char = chars[index]
            if inQuotes {
                if char == "\"" {
                    if index + 1 < chars.count, chars[index + 1] == "\"" {
                        current.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(char)
                }
            } else if char == "\"" && current.isEmpty {
                inQuotes = true
            } else if char == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
            index += 1
        }
        fields.append(current)

        guard fields.count >= 2 else { return nil }
        let title = fields[0].trimmingCharacters(in: .whitespaces)
        // Only the title field may be quoted; everything after its comma is
        // the url, rejoined in case the url itself contains an unquoted comma.
        let url = fields[1...].joined(separator: ",").trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !url.isEmpty else { return nil }
        return (title, url)
    }
}

/// Ranks bookmarks against a query by fuzzy-matching their title first and
/// their url second. Pure so ordering is exercised in tests. Every bookmark
/// whose title matches sorts above every bookmark that only matches by url —
/// title is what "fuzzy match on title first" means — so a url substring can
/// surface a bookmark (handy when you remember the domain, not the title) but
/// never outranks an actual title match.
enum BookmarkFilter {
    /// The bookmarks matching `query` by title or url, best title match
    /// first, then best url-only match; the full list in file order when the
    /// query is empty. Ties keep their original order (stable).
    static func filter(_ bookmarks: [Bookmark], query: String) -> [Bookmark] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return bookmarks }

        struct Scored { let bookmark: Bookmark; let matchedTitle: Bool; let score: Int; let index: Int }
        return bookmarks.enumerated()
            .compactMap { index, bookmark -> Scored? in
                if let score = FuzzyMatch.score(bookmark.title, query: trimmed) {
                    return Scored(bookmark: bookmark, matchedTitle: true, score: score, index: index)
                }
                if let score = FuzzyMatch.score(bookmark.url, query: trimmed) {
                    return Scored(bookmark: bookmark, matchedTitle: false, score: score, index: index)
                }
                return nil
            }
            .sorted {
                if $0.matchedTitle != $1.matchedTitle { return $0.matchedTitle }
                return $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index
            }
            .map(\.bookmark)
    }
}
