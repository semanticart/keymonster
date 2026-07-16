import Foundation

enum ClipContent {
    case text(String)
    case image(Data)
    case fileURLs([URL])
}

extension ClipContent: Equatable {
    static func == (lhs: ClipContent, rhs: ClipContent) -> Bool {
        switch (lhs, rhs) {
        case (.text(let left), .text(let right)):
            return left == right
        // Plain Data equality — cheap, unlike the tiffRepresentation comparison
        // this replaced, which re-encoded both images on every dedup check.
        case (.image(let left), .image(let right)):
            return left == right
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
    let richTextData: Data?
    let richTextType: String?

    init(
        id: UUID = UUID(),
        content: ClipContent,
        date: Date,
        sourceAppName: String?,
        sourceAppBundleID: String?,
        richTextData: Data? = nil,
        richTextType: String? = nil
    ) {
        self.id = id
        self.content = content
        self.date = date
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
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

extension ClipItem {
    func asRecord() -> ClipRecord {
        switch content {
        case .text(let text):
            return ClipRecord(
                id: id, date: date, contentType: "text", textContent: text,
                sourceAppName: sourceAppName, sourceAppBundleID: sourceAppBundleID,
                richTextData: richTextData, richTextType: richTextType
            )
        case .image(let data):
            return ClipRecord(
                id: id, date: date, contentType: "image", imageData: data,
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
        switch record.contentType {
        case "text":
            guard let text = record.textContent else { return nil }
            self.init(
                id: record.id, content: .text(text), date: record.date,
                sourceAppName: record.sourceAppName,
                sourceAppBundleID: record.sourceAppBundleID,
                richTextData: record.richTextData, richTextType: record.richTextType
            )
        case "image":
            guard let data = record.imageData else { return nil }
            self.init(
                id: record.id, content: .image(data), date: record.date,
                sourceAppName: record.sourceAppName,
                sourceAppBundleID: record.sourceAppBundleID
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
                sourceAppBundleID: record.sourceAppBundleID
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
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        richTextData: Data? = nil,
        richTextType: String? = nil
    ) {
        if case .text(let text) = content,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

        // When deduplicating, preserve the original item's source app so that
        // re-selecting from the history panel doesn't overwrite the origin
        // name/bundle ID with Key Monster's own.
        var preservedName = sourceAppName
        var preservedBundleID = sourceAppBundleID

        if let existing = items.firstIndex(where: { $0.content == content }) {
            let old = items.remove(at: existing)
            deleteFromStore(id: old.id)
            preservedName = old.sourceAppName
            preservedBundleID = old.sourceAppBundleID
        }

        let newItem = ClipItem(
            content: content, date: Date(),
            sourceAppName: preservedName,
            sourceAppBundleID: preservedBundleID,
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
