import Foundation

/// Turns the accessibility description Slack gives an emoji back into text.
///
/// Slack's composer (Chromium) exposes an emoji as a childless `AXImage` with
/// an empty value and a description made from Slack's short name: "tada
/// emoji", "+1 emoji with medium skin tone", "people holding hands emoji with
/// left light skin tone and right dark skin tone". The name has every `_` and
/// `-` flattened to a space, and an alias the user typed (`:thumbsup:`) stays
/// that alias. Nothing else on the element says which emoji it is — the
/// image URL is a 1×1 placeholder — so the description is decoded against
/// emoji-data, the table Slack itself is built from (`EmojiNamesTable`,
/// regenerated with `make emoji-names`). Captured 2026-09-07.
///
/// A name the table doesn't know is a workspace's custom emoji, which has no
/// character; it becomes the `:name:` shortcode, which Slack turns back into
/// the emoji when the text is pasted. The flattening is lossy there — a
/// custom `party-parrot` reads as "party parrot" — so multi-word custom names
/// are a best guess with underscores.
enum EmojiNames {
    /// The text for an emoji image's description, or nil when the description
    /// isn't one of Slack's ("image" for a regular picture).
    static func text(forDescription description: String) -> String? {
        guard let parsed = parse(description) else { return nil }
        if let sequence = sequence(name: parsed.name, tones: parsed.tones) {
            return String(String.UnicodeScalarView(sequence))
        }
        return ":" + parsed.name.replacingOccurrences(of: " ", with: "_") + ":"
    }

    // MARK: - Parsing

    private struct Parsed {
        let name: String
        /// Skin-tone modifier code points, in order; empty for the plain emoji.
        let tones: [String]
    }

    private static let toneCodePoints = [
        "light": "1F3FB",
        "medium-light": "1F3FC",
        "medium": "1F3FD",
        "medium-dark": "1F3FE",
        "dark": "1F3FF"
    ]

    /// "NAME emoji", "NAME emoji with TONE skin tone", or
    /// "NAME emoji with left TONE skin tone and right TONE skin tone".
    private static func parse(_ description: String) -> Parsed? {
        let parts = description.components(separatedBy: " emoji")
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        let name = parts[0]
        let suffix = parts[1]
        if suffix.isEmpty { return Parsed(name: name, tones: []) }

        guard suffix.hasPrefix(" with "), suffix.hasSuffix(" skin tone") else { return nil }
        var tones: [String] = []
        let spec = suffix.dropFirst(" with ".count).dropLast(" skin tone".count)
        if spec.hasPrefix("left ") {
            let sides = spec.dropFirst("left ".count).components(separatedBy: " skin tone and right ")
            guard sides.count == 2 else { return nil }
            tones = sides
        } else {
            tones = [String(spec)]
        }
        let codePoints = tones.compactMap { toneCodePoints[$0] }
        guard codePoints.count == tones.count else { return nil }
        return Parsed(name: name, tones: codePoints)
    }

    // MARK: - Lookup

    private static func sequence(name: String, tones: [String]) -> [Unicode.Scalar]? {
        let table = Table.shared
        let key = Table.key(name)
        if !tones.isEmpty, let explicit = table.entries[key + "|" + tones.joined(separator: "-")] {
            return explicit
        }
        guard let base = table.entries[key] else { return nil }
        return tones.isEmpty ? base : applying(tones: tones, to: base)
    }

    /// The first tone goes after the first code point, displacing a variation
    /// selector (a toned emoji is never text-presentation); a second tone goes
    /// at the end. Right for all but the mixed-tone hand-holding pairs, which
    /// the table lists explicitly.
    private static func applying(tones: [String], to base: [Unicode.Scalar]) -> [Unicode.Scalar] {
        let toneScalars = tones.compactMap { Unicode.Scalar(UInt32($0, radix: 16) ?? 0) }
        guard toneScalars.count == tones.count, let first = base.first else { return base }
        var rest = Array(base.dropFirst())
        if rest.first == "\u{FE0F}" { rest.removeFirst() }
        var result = [first, toneScalars[0]] + rest
        if toneScalars.count > 1 { result.append(toneScalars[1]) }
        return result
    }

    /// The table, parsed once on first use. Keys are the flattened names Slack
    /// shows ("e mail", "non potable water"), one per alias; skin-tone
    /// exceptions are keyed `name|tones`.
    struct Table {
        let entries: [String: [Unicode.Scalar]]

        static let shared = Table(contents: EmojiNamesTable.contents)

        init(contents: String) {
            var entries: [String: [Unicode.Scalar]] = [:]
            for line in contents.split(separator: "\n") {
                let fields = line.split(separator: " ", maxSplits: 1)
                guard fields.count == 2 else { continue }
                let scalars = fields[1].split(separator: "-").compactMap {
                    UInt32($0, radix: 16).flatMap(Unicode.Scalar.init)
                }
                guard !scalars.isEmpty else { continue }
                if let bar = fields[0].firstIndex(of: "|") {
                    entries[Self.key(String(fields[0][..<bar])) + String(fields[0][bar...])] = scalars
                } else {
                    for name in fields[0].split(separator: ",") {
                        entries[Self.key(String(name))] = scalars
                    }
                }
            }
            self.entries = entries
        }

        /// How Slack flattens a short name for the description.
        static func key(_ name: String) -> String {
            name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        }
    }
}
