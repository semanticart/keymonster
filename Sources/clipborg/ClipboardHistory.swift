import Foundation
import AppKit
import SwiftData

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

struct ClipItem: Identifiable {
    let id: UUID
    let content: ClipContent
    let date: Date
    let sourceAppName: String?
    let sourceAppBundleID: String?
    let sourceAppIcon: NSImage?

    init(id: UUID = UUID(), content: ClipContent, date: Date, sourceAppName: String?, sourceAppBundleID: String?, sourceAppIcon: NSImage?) {
        self.id = id
        self.content = content
        self.date = date
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppIcon = sourceAppIcon
    }
}

extension ClipItem: Equatable {
    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id
    }
}

extension ClipItem {
    func asPersisted() -> PersistedClipItem {
        switch content {
        case .text(let s):
            return PersistedClipItem(id: id, date: date, contentType: "text", textContent: s, sourceAppName: sourceAppName, sourceAppBundleID: sourceAppBundleID)
        case .image(let img):
            return PersistedClipItem(id: id, date: date, contentType: "image", imageData: img.tiffRepresentation, sourceAppName: sourceAppName, sourceAppBundleID: sourceAppBundleID)
        case .fileURLs(let urls):
            let data = try? JSONEncoder().encode(urls.map(\.absoluteString))
            let json = data.flatMap { String(data: $0, encoding: .utf8) }
            return PersistedClipItem(id: id, date: date, contentType: "fileURLs", fileURLsJSON: json, sourceAppName: sourceAppName, sourceAppBundleID: sourceAppBundleID)
        }
    }

    init?(from persisted: PersistedClipItem) {
        let icon = iconForBundleID(persisted.sourceAppBundleID)
        switch persisted.contentType {
        case "text":
            guard let text = persisted.textContent else { return nil }
            self.init(id: persisted.id, content: .text(text), date: persisted.date, sourceAppName: persisted.sourceAppName, sourceAppBundleID: persisted.sourceAppBundleID, sourceAppIcon: icon)
        case "image":
            guard let data = persisted.imageData, let image = NSImage(data: data) else { return nil }
            self.init(id: persisted.id, content: .image(image), date: persisted.date, sourceAppName: persisted.sourceAppName, sourceAppBundleID: persisted.sourceAppBundleID, sourceAppIcon: icon)
        case "fileURLs":
            guard let jsonStr = persisted.fileURLsJSON,
                  let data = jsonStr.data(using: .utf8),
                  let strings = try? JSONDecoder().decode([String].self, from: data)
            else { return nil }
            self.init(id: persisted.id, content: .fileURLs(strings.compactMap(URL.init(string:))), date: persisted.date, sourceAppName: persisted.sourceAppName, sourceAppBundleID: persisted.sourceAppBundleID, sourceAppIcon: icon)
        default:
            return nil
        }
    }
}

/// Observable store of recent clipboard entries, newest first, with dedup and a size cap.
@MainActor
final class ClipboardHistory: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private var modelContext: ModelContext?
    private let maxItems = 10_000

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadFromStore()
    }

    private func loadFromStore() {
        guard let ctx = modelContext else { return }
        let descriptor = FetchDescriptor<PersistedClipItem>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let persisted = try? ctx.fetch(descriptor) else { return }
        items = persisted.compactMap { ClipItem(from: $0) }
    }

    func add(_ content: ClipContent, sourceApp: NSRunningApplication? = nil) {
        if case .text(let s) = content,
           s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

        if let existing = items.firstIndex(where: { $0.content == content }) {
            let old = items.remove(at: existing)
            deleteFromStore(id: old.id)
        }

        let newItem = ClipItem(content: content, date: Date(), sourceAppName: sourceApp?.localizedName, sourceAppBundleID: sourceApp?.bundleIdentifier, sourceAppIcon: sourceApp?.icon)
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
        guard let ctx = modelContext else { return }
        try? ctx.delete(model: PersistedClipItem.self)
        try? ctx.save()
    }

    private func insertIntoStore(_ item: ClipItem) {
        guard let ctx = modelContext else { return }
        ctx.insert(item.asPersisted())
        try? ctx.save()
    }

    private func deleteFromStore(id: UUID) {
        guard let ctx = modelContext else { return }
        let targetID = id
        let descriptor = FetchDescriptor<PersistedClipItem>(
            predicate: #Predicate { $0.id == targetID }
        )
        if let found = try? ctx.fetch(descriptor).first {
            ctx.delete(found)
            try? ctx.save()
        }
    }
}
