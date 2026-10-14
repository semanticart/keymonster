import CoreGraphics
import Foundation

/// A run of cells on one screen row: `startColumn` through `endColumn`, exclusive.
struct CellSpan: Equatable {
    let row: Int
    let startColumn: Int
    let endColumn: Int
}

/// A link on a terminal's screen — either an explicit OSC 8 hyperlink or a bare
/// URL printed in the text — located on the cell grid. A link that wraps over
/// several rows has one span per row, in reading order.
struct TerminalLink: Equatable {
    let url: String
    let spans: [CellSpan]
}

/// Finds links in a terminal's screen text (`kitten @ get-text --ansi`) and says
/// where each sits on the cell grid. Pure, so every wrapping and escape-sequence
/// quirk is testable from captured output.
///
/// The text arrives with soft-wrapped rows already joined into one logical line
/// and hard line breaks as `\n`, so the grid position of a character comes from
/// counting cells and wrapping at `columns`. Colors and cursor styling are
/// escape noise to skip — notably tmux re-emits a bare `ESC[m` at its wrap
/// boundary, even in the middle of a URL — while OSC 8 hyperlink spans are the
/// one escape that carries meaning.
enum TerminalLinks {
    /// Stops at whitespace, quotes, angle brackets, and box-drawing glyphs (TUIs
    /// draw their borders right up against the text).
    private static let urlPattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "(?:https?|file)://[^\\s<>\"'`\\u2500-\\u257F]+"
    )

    private struct Cell {
        let character: Character
        let row: Int
        let column: Int
        let width: Int
        /// First cell after a hard line break, so a URL can't run across it.
        let startsLine: Bool
        /// Index of the OSC 8 hyperlink this cell belongs to, if any.
        let hyperlink: Int?
    }

    private struct Hyperlink {
        let url: String
        var cells: [Int] = []
    }

    static func find(inANSI text: String, columns: Int) -> [TerminalLink] {
        guard columns > 0 else { return [] }
        let (cells, hyperlinks) = layOut(text, columns: columns)
        var links = hyperlinks.compactMap { link -> TerminalLink? in
            guard !link.cells.isEmpty else { return nil }
            return TerminalLink(url: link.url, spans: spans(of: link.cells.map { cells[$0] }))
        }
        links += bareURLs(in: cells)
        return links.sorted { lhs, rhs in
            guard let left = lhs.spans.first, let right = rhs.spans.first else { return false }
            return (left.row, left.startColumn) < (right.row, right.startColumn)
        }
    }

    // MARK: - Layout

    /// Walks the text, dropping escapes and placing every printable character
    /// on the grid. Hyperlink spans are returned as the cells they cover.
    private static func layOut(_ text: String, columns: Int) -> ([Cell], [Hyperlink]) {
        var cells: [Cell] = []
        var hyperlinks: [Hyperlink] = []
        var openLink: Int?
        var row = 0
        var column = 0
        var startsLine = true

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            index = text.index(after: index)

            switch character {
            case "\u{1b}":
                let (body, next) = escape(in: text, after: index)
                index = next
                if let url = hyperlinkTarget(body) {
                    if url.isEmpty {
                        openLink = nil
                    } else {
                        hyperlinks.append(Hyperlink(url: url))
                        openLink = hyperlinks.count - 1
                    }
                }
            case "\n", "\r\n":
                row += 1
                column = 0
                startsLine = true
            default:
                let width = CellWidth.of(character)
                if column + width > columns {
                    row += 1
                    column = 0
                }
                cells.append(Cell(
                    character: character, row: row, column: column, width: width,
                    startsLine: startsLine, hyperlink: openLink
                ))
                if let openLink { hyperlinks[openLink].cells.append(cells.count - 1) }
                column += width
                startsLine = false
            }
        }
        return (cells, hyperlinks)
    }

    /// Consumes the escape sequence starting just after an ESC, returning the
    /// OSC body (nil for anything else) and where the text resumes.
    private static func escape(in text: String, after start: String.Index) -> (String?, String.Index) {
        guard start < text.endIndex else { return (nil, start) }
        var index = text.index(after: start)

        switch text[start] {
        case "[":
            // CSI: parameters, then one final byte in @…~.
            while index < text.endIndex {
                let scalar = text[index].unicodeScalars.first!.value
                index = text.index(after: index)
                if (0x40...0x7E).contains(scalar) { break }
            }
            return (nil, index)
        case "]":
            // OSC: up to a BEL or the ST (ESC \) terminator.
            var body = ""
            while index < text.endIndex {
                let character = text[index]
                if character == "\u{07}" {
                    return (body, text.index(after: index))
                }
                if character == "\u{1b}" {
                    let next = text.index(after: index)
                    return (body, next < text.endIndex ? text.index(after: next) : next)
                }
                body.append(character)
                index = text.index(after: index)
            }
            return (body, index)
        default:
            return (nil, index) // two-character escape; nothing more to skip
        }
    }

    /// The URL an OSC 8 body opens (`8;params;url`), "" when it closes the
    /// link, nil when the body is some other OSC.
    private static func hyperlinkTarget(_ body: String?) -> String? {
        guard let body, body.hasPrefix("8;") else { return nil }
        let fields = body.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3 else { return nil }
        return String(fields[2])
    }

    // MARK: - Bare URLs

    /// URLs printed as plain text, searched with the hyperlink cells blanked out
    /// and a newline at every hard break so a match can't run across either.
    /// Soft-wrapped rows stay joined, which is how a wrapped URL is found whole.
    private static func bareURLs(in cells: [Cell]) -> [TerminalLink] {
        var haystack = ""
        var starts: [Int] = []  // UTF-16 offset of each cell in `haystack`
        for cell in cells {
            if cell.startsLine { haystack.append("\n") }
            starts.append(haystack.utf16.count)
            haystack.append(cell.hyperlink == nil ? cell.character : "\n")
        }

        let whole = NSRange(location: 0, length: haystack.utf16.count)
        return urlPattern.matches(in: haystack, range: whole).compactMap { match in
            guard let range = Range(match.range, in: haystack) else { return nil }
            let url = trimmed(String(haystack[range]))
            guard !url.isEmpty else { return nil }
            let end = match.range.location + url.utf16.count
            let covered = cells.indices.filter { starts[$0] >= match.range.location && starts[$0] < end }
            guard !covered.isEmpty else { return nil }
            return TerminalLink(url: url, spans: spans(of: covered.map { cells[$0] }))
        }
    }

    private static let openers: [Character: Character] = [")": "(", "]": "[", "}": "{"]

    /// Drops punctuation that belongs to the sentence around a URL, not the
    /// URL: trailing `.,;:!?`, and a closing bracket with no opener to match.
    private static func trimmed(_ url: String) -> String {
        var result = url
        while let last = result.last {
            if ".,;:!?".contains(last) {
                result.removeLast()
            } else if let opener = openers[last],
                      result.filter({ $0 == last }).count > result.filter({ $0 == opener }).count {
                result.removeLast()
            } else {
                break
            }
        }
        return result
    }

    // MARK: - Spans

    /// Collapses cells (in reading order) into one span per row.
    private static func spans(of cells: [Cell]) -> [CellSpan] {
        var spans: [CellSpan] = []
        for cell in cells {
            let end = cell.column + cell.width
            if let last = spans.last, last.row == cell.row {
                spans[spans.count - 1] = CellSpan(
                    row: last.row, startColumn: last.startColumn, endColumn: max(last.endColumn, end)
                )
            } else {
                spans.append(CellSpan(row: cell.row, startColumn: cell.column, endColumn: end))
            }
        }
        return spans
    }
}

/// Something in the screen text that reads like a file path, before anyone has
/// checked it names a real file.
struct TerminalPathCandidate: Equatable {
    /// As printed: may be relative or start with `~`.
    let text: String
    let line: Int?
    let column: Int?
    let spans: [CellSpan]
}

extension TerminalLinks {
    /// Paths with at least one slash (`/etc/hosts`, `~/x`, `./a`, `src/a.swift`)
    /// or a bare `name.ext`, each with an optional `:line[:column]` tail as
    /// compilers, grep, and test runners print. Deliberately greedy: callers
    /// confirm candidates against the file system, which is what keeps prose
    /// like "and/or" or "e.g." from being hinted.
    private static let pathPattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: "(?<![\\w:/~.\\-@])"
            + "((?:(?:~|\\.{1,2}|[\\w@+-][\\w.@+-]*)?(?:/[\\w.@+%~=,#-]+)+/?"
            + "|[\\w@+-][\\w.@+-]*\\.[A-Za-z0-9]{1,8}))"
            + "(?::(\\d+)(?::(\\d+))?)?"
    )

    /// Path-like text on screen. Hyperlink labels are skipped (they're already
    /// links), and the lookbehind keeps the tail of a URL from matching.
    static func findPaths(inANSI text: String, columns: Int) -> [TerminalPathCandidate] {
        guard columns > 0 else { return [] }
        let (cells, _) = layOut(text, columns: columns)
        var haystack = ""
        var starts: [Int] = []
        for cell in cells {
            if cell.startsLine { haystack.append("\n") }
            starts.append(haystack.utf16.count)
            haystack.append(cell.hyperlink == nil ? cell.character : "\n")
        }

        let whole = NSRange(location: 0, length: haystack.utf16.count)
        return pathPattern.matches(in: haystack, range: whole).compactMap { match in
            guard let range = Range(match.range(at: 1), in: haystack) else { return nil }
            var path = String(haystack[range])
            // A sentence's full stop or comma rides along on the last segment.
            while let last = path.last, ".,;".contains(last), match.range(at: 2).location == NSNotFound {
                path.removeLast()
            }
            guard !path.isEmpty else { return nil }
            func number(_ group: Int) -> Int? {
                guard let range = Range(match.range(at: group), in: haystack) else { return nil }
                return Int(haystack[range])
            }
            var end = match.range(at: 1).location + path.utf16.count
            if match.range(at: 2).location != NSNotFound {
                end = match.range.location + match.range.length
            }
            let covered = cells.indices.filter { starts[$0] >= match.range.location && starts[$0] < end }
            guard !covered.isEmpty else { return nil }
            return TerminalPathCandidate(
                text: path, line: number(2), column: number(3),
                spans: spans(of: covered.map { cells[$0] })
            )
        }
    }
}

/// Turns printed path text into an absolute path that exists. Pure: the file
/// system is a closure.
enum TerminalPathResolver {
    static func resolve(
        _ text: String, cwd: String?, home: String, exists: (String) -> Bool
    ) -> String? {
        let expanded: String
        if text == "~" || text.hasPrefix("~/") {
            expanded = home + text.dropFirst()
        } else if text.hasPrefix("/") {
            expanded = text
        } else if let cwd {
            expanded = cwd + "/" + text
        } else {
            return nil
        }
        let path = (expanded as NSString).standardizingPath
        return exists(path) ? path : nil
    }
}

/// How many terminal cells a character covers: 2 for East Asian wide glyphs and
/// emoji, 1 otherwise. Works on grapheme clusters, so a combining sequence
/// counts by its base.
enum CellWidth {
    static func of(_ character: Character) -> Int {
        let scalars = character.unicodeScalars
        // Variation selector 16 asks for the emoji (wide) presentation.
        if scalars.contains(where: { $0.value == 0xFE0F }) { return 2 }
        guard let base = scalars.first?.value else { return 1 }
        return wideRanges.contains { $0.contains(base) } ? 2 : 1
    }

    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF,
        0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
        0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD
    ]
}

/// The terminal's cell grid placed on screen, to turn spans into rects.
struct TerminalGrid: Equatable {
    /// The text area in AX (global, top-left origin) coordinates.
    let frame: CGRect
    let columns: Int
    let lines: Int

    func rect(for span: CellSpan) -> CGRect {
        let cellWidth = frame.width / CGFloat(max(columns, 1))
        let cellHeight = frame.height / CGFloat(max(lines, 1))
        return CGRect(
            x: frame.minX + CGFloat(span.startColumn) * cellWidth,
            y: frame.minY + CGFloat(span.row) * cellHeight,
            width: CGFloat(span.endColumn - span.startColumn) * cellWidth,
            height: cellHeight
        )
    }

    /// One target per link, labeled on its first row — where it reads naturally.
    /// Committing opens `link.url` itself, so where on the link the badge sits
    /// doesn't matter to the result.
    func targets(for links: [TerminalLink]) -> [HintTarget] {
        links.compactMap { link in
            guard let span = link.spans.first, span.row < lines else { return nil }
            return HintTarget(frame: rect(for: span), role: "AXLink", linkURL: link.url)
        }
    }

    /// One target per confirmed file, labeled on its first row.
    func targets(for files: [(file: FileTarget, spans: [CellSpan])]) -> [HintTarget] {
        files.compactMap { entry in
            guard let span = entry.spans.first, span.row < lines else { return nil }
            return HintTarget(frame: rect(for: span), role: "AXLink", file: entry.file)
        }
    }
}
