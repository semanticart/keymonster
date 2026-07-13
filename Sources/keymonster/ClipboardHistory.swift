import Foundation
import AppKit

private func iconForBundleID(_ bundleID: String?) -> NSImage? {
    guard let id = bundleID,
          let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    else { return nil }
    return NSWorkspace.shared.icon(forFile: url.path)
}

enum ClipContent {
    case text(String)
    case image(NSImage)
    case fileURLs([URL])
}

extension ClipContent: Equatable {
    static func == (lhs: ClipContent, rhs: ClipContent) -> Bool {
        switch (lhs, rhs) {
        case (.text(let left), .text(let right)):
            return left == right
        case (.image(let left), .image(let right)):
            return left.tiffRepresentation == right.tiffRepresentation
        case (.fileURLs(let left), .fileURLs(let right)):
            return Set(left) == Set(right)
        default:
            return false
        }
    }
}

struct ClipItem: Identifiable {
    let id: UUID
    let content: ClipContent
    let date: Date
    let sourceAppName: String?
    let sourceAppBundleID: String?
    let sourceAppIcon: NSImage?
    let richTextData: Data?
    let richTextType: String?

    init(
        id: UUID = UUID(),
        content: ClipContent,
        date: Date,
        sourceAppName: String?,
        sourceAppBundleID: String?,
        sourceAppIcon: NSImage?,
        richTextData: Data? = nil,
        richTextType: String? = nil
    ) {
        self.id = id
        self.content = content
        self.date = date
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppIcon = sourceAppIcon
        self.richTextData = richTextData
        self.richTextType = richTextType
    }
}

extension ClipItem: Equatable {
    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension ClipItem {
    /// Whether this item matches a search query. `query` must already be
    /// lowercased and whitespace-trimmed. Matches text content, file names, and
    /// the source app name; images only match via their source app.
    func matches(lowercasedQuery query: String) -> Bool {
        if let name = sourceAppName?.lowercased(), name.contains(query) { return true }
        switch content {
        case .text(let text):
            return text.lowercased().contains(query)
        case .image:
            return false
        case .fileURLs(let urls):
            return urls.contains { $0.lastPathComponent.lowercased().contains(query) }
        }
    }
}

/// Writes a clip's content onto the general pasteboard. The watcher will see the
/// write and move the item to the top (most-recently-used).
@MainActor
func copyToPasteboard(_ item: ClipItem) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    switch item.content {
    case .text(let text):
        pasteboard.setString(text, forType: .string)
        if let data = item.richTextData, let typeStr = item.richTextType {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(rawValue: typeStr))
        }
    case .image(let img):
        pasteboard.writeObjects([img])
    case .fileURLs(let urls):
        pasteboard.writeObjects(urls as [NSURL])
    }
}

extension ClipItem {
    func asRecord() -> ClipRecord {
        switch content {
        case .text(let text):
            return ClipRecord(
                id: id, date: date, contentType: "text", textContent: text,
                sourceAppName: sourceAppName, sourceAppBundleID: sourceAppBundleID,
                richTextData: richTextData, richTextType: richTextType
            )
        case .image(let img):
            return ClipRecord(
                id: id, date: date, contentType: "image", imageData: img.tiffRepresentation,
                sourceAppName: sourceAppName, sourceAppBundleID: sourceAppBundleID
            )
        case .fileURLs(let urls):
            let data = try? JSONEncoder().encode(urls.map(\.absoluteString))
            let json = data.flatMap { String(data: $0, encoding: .utf8) }
            return ClipRecord(
                id: id, date: date, contentType: "fileURLs", fileURLsJSON: json,
                sourceAppName: sourceAppName, sourceAppBundleID: sourceAppBundleID
            )
        }
    }

    init?(from record: ClipRecord) {
        let icon = iconForBundleID(record.sourceAppBundleID)
        switch record.contentType {
        case "text":
            guard let text = record.textContent else { return nil }
            self.init(
                id: record.id, content: .text(text), date: record.date,
                sourceAppName: record.sourceAppName,
                sourceAppBundleID: record.sourceAppBundleID, sourceAppIcon: icon,
                richTextData: record.richTextData, richTextType: record.richTextType
            )
        case "image":
            guard let data = record.imageData, let image = NSImage(data: data) else { return nil }
            self.init(
                id: record.id, content: .image(image), date: record.date,
                sourceAppName: record.sourceAppName,
                sourceAppBundleID: record.sourceAppBundleID, sourceAppIcon: icon
            )
        case "fileURLs":
            guard let jsonStr = record.fileURLsJSON,
                  let data = jsonStr.data(using: .utf8),
                  let strings = try? JSONDecoder().decode([String].self, from: data)
            else { return nil }
            self.init(
                id: record.id,
                content: .fileURLs(strings.compactMap(URL.init(string:))),
                date: record.date,
                sourceAppName: record.sourceAppName,
                sourceAppBundleID: record.sourceAppBundleID, sourceAppIcon: icon
            )
        default:
            return nil
        }
    }
}

/// Observable store of recent clipboard entries, newest first, with dedup and a size cap.
@MainActor
final class ClipboardHistory: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private var store: ClipStore?
    private let maxItems = 10_000

    func configure(store: ClipStore) {
        self.store = store
        loadFromStore()
    }

    private func loadFromStore() {
        guard let store, let records = try? store.load() else { return }
        items = records.compactMap { ClipItem(from: $0) }
    }

    func add(
        _ content: ClipContent,
        sourceApp: NSRunningApplication? = nil,
        richTextData: Data? = nil,
        richTextType: String? = nil
    ) {
        if case .text(let text) = content,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

        // When deduplicating, preserve the original item's source app so that
        // re-selecting from the history panel doesn't overwrite the origin icon
        // with Key Monster's own icon.
        var preservedName: String? = sourceApp?.localizedName
        var preservedBundleID: String? = sourceApp?.bundleIdentifier
        var preservedIcon: NSImage? = sourceApp?.icon

        if let existing = items.firstIndex(where: { $0.content == content }) {
            let old = items.remove(at: existing)
            deleteFromStore(id: old.id)
            preservedName = old.sourceAppName
            preservedBundleID = old.sourceAppBundleID
            preservedIcon = old.sourceAppIcon
        }

        let newItem = ClipItem(
            content: content, date: Date(),
            sourceAppName: preservedName,
            sourceAppBundleID: preservedBundleID,
            sourceAppIcon: preservedIcon,
            richTextData: richTextData,
            richTextType: richTextType
        )
        items.insert(newItem, at: 0)
        insertIntoStore(newItem)

        if items.count > maxItems {
            let overflow = items.count - maxItems
            let toRemove = Array(items.suffix(overflow))
            items.removeLast(overflow)
            for item in toRemove { deleteFromStore(id: item.id) }
        }
    }

    func clear() {
        items.removeAll()
        try? store?.deleteAll()
    }

    private func insertIntoStore(_ item: ClipItem) {
        try? store?.insert(item.asRecord())
    }

    private func deleteFromStore(id: UUID) {
        try? store?.delete(id: id)
    }
}
