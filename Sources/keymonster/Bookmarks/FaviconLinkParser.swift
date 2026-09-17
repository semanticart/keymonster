import Foundation

/// Extracts the icon url a page's `<head>` declares via a `<link>` tag —
/// `FaviconStore`'s fallback for sites that don't serve a conventional
/// `/favicon.ico` (site builders like Webflow and Squarespace only declare
/// an icon this way, often on a different host/CDN entirely). Regex-based
/// rather than a real HTML parser: this one tag shape is all that's ever
/// needed, and pulling in an HTML parsing dependency for it isn't worth it.
/// Pure and Foundation-only so it's unit-tested against literal HTML strings.
enum FaviconLinkParser {
    /// `rel` values, in priority order: a plain icon wins over an Apple
    /// touch icon (usually a large iOS-home-screen image) regardless of
    /// which `<link>` appears first in the document.
    private static let relTiers: [[String]] = [
        ["icon", "shortcut icon"],
        ["apple-touch-icon", "apple-touch-icon-precomposed"]
    ]

    /// The best icon url declared in `html`'s `<link>` tags, resolved against
    /// `pageURL` (so a relative or protocol-relative href still works), or
    /// nil if none of the recognized rel values are present.
    static func iconURL(in html: String, pageURL: URL) -> URL? {
        let tags = linkTags(in: html)
        for tier in relTiers {
            for tag in tags {
                guard let rel = attribute("rel", in: tag)?.lowercased(), tier.contains(rel),
                      let href = attribute("href", in: tag),
                      let url = URL(string: href, relativeTo: pageURL) else { continue }
                return url.absoluteURL
            }
        }
        return nil
    }

    private static func linkTags(in html: String) -> [String] {
        matches(pattern: "<link\\b[^>]*>", in: html)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        if let value = firstGroup(pattern: "\\b\(name)\\s*=\\s*\"([^\"]*)\"", in: tag) { return value }
        return firstGroup(pattern: "\\b\(name)\\s*=\\s*'([^']*)'", in: tag)
    }

    private static func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func firstGroup(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let group = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[group])
    }
}
