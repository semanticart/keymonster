import Foundation
import AppKit

enum ClipContent {
    case text(String)
    case image(NSImage)
    case fileURLs([URL])
}

extension ClipContent: Equatable {
    static func == (lhs: ClipContent, rhs: ClipContent) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)):
            return a == b
        case (.image(let a), .image(let b)):
            return a.tiffRepresentation == b.tiffRepresentation
        case (.fileURLs(let a), .fileURLs(let b)):
            return Set(a) == Set(b)
        default:
            return false
        }
    }
}

/// A single captured clipboard entry.
struct ClipItem: Identifiable {
    let id = UUID()
    let content: ClipContent
    let date: Date
    let sourceAppName: String?
    let sourceAppIcon: NSImage?
}

extension ClipItem: Equatable {
    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Observable store of recent clipboard entries, newest first, with dedup and a size cap.
@MainActor
final class ClipboardHistory: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private let maxItems = 100

    func add(_ content: ClipContent, sourceApp: NSRunningApplication? = nil) {
        // Ignore whitespace-only text copies.
        if case .text(let s) = content,
           s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

        // If we've seen this exact content before, move it to the top instead of duplicating.
        if let existing = items.firstIndex(where: { $0.content == content }) {
            items.remove(at: existing)
        }
        items.insert(ClipItem(content: content, date: Date(), sourceAppName: sourceApp?.localizedName, sourceAppIcon: sourceApp?.icon), at: 0)

        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
    }

    func clear() {
        items.removeAll()
    }
}
