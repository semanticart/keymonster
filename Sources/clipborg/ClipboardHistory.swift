import Foundation

/// A single captured clipboard entry.
struct ClipItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let date: Date
}

/// Observable store of recent clipboard text, newest first, with dedup and a size cap.
@MainActor
final class ClipboardHistory: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private let maxItems = 100

    func add(_ text: String) {
        // Ignore whitespace-only copies.
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // If we've seen this exact text before, move it to the top instead of duplicating.
        if let existing = items.firstIndex(where: { $0.text == text }) {
            items.remove(at: existing)
        }
        items.insert(ClipItem(text: text, date: Date()), at: 0)

        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
    }

    func clear() {
        items.removeAll()
    }
}
