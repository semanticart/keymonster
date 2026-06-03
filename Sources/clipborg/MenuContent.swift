import SwiftUI
import AppKit
import os.log

private let log = Logger(subsystem: "clipborg", category: "menu")

/// The centered panel's contents: a header with a search field, a scrollable
/// (and filterable) history list, and a footer with Clear / Quit. Rendered on a
/// rounded translucent material. Keyboard navigation is driven by `model` and the
/// panel's event monitor (Ctrl-N / Ctrl-P, arrows, Return).
struct MenuContent: View {
    @ObservedObject var history: ClipboardHistory
    @ObservedObject var model: HistoryViewModel

    /// Called after the user picks an item so the panel can dismiss.
    var onClose: () -> Void = {}

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 420 * uiScale, height: 540 * uiScale)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16 * uiScale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16 * uiScale, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
        .onChange(of: model.focusBump) { searchFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10 * uiScale) {
            HStack(spacing: 10 * uiScale) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 16 * uiScale, weight: .semibold))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 1 * uiScale) {
                    Text("Clipboard History")
                        .font(.system(size: 17 * uiScale, weight: .semibold))
                    let count = history.items.count
                    Text(history.items.isEmpty ? "Empty" : "\(count) item\(count == 1 ? "" : "s")")
                        .font(.system(size: 12 * uiScale))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            searchField
        }
        .padding(.horizontal, 18 * uiScale)
        .padding(.vertical, 14 * uiScale)
    }

    private var searchField: some View {
        HStack(spacing: 7 * uiScale) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13 * uiScale))
                .foregroundStyle(.secondary)

            TextField("Search", text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14 * uiScale))
                .focused($searchFocused)

            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13 * uiScale))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10 * uiScale)
        .padding(.vertical, 7 * uiScale)
        .background(
            RoundedRectangle(cornerRadius: 8 * uiScale, style: .continuous)
                .fill(.primary.opacity(0.06))
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if history.items.isEmpty {
            emptyState
        } else if model.filteredItems.isEmpty {
            noMatchesState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4 * uiScale) {
                        ForEach(model.filteredItems) { item in
                            HistoryRow(item: item, isSelected: item.id == model.selectedID) {
                                copyToPasteboard(item.content)
                                onClose()
                            }
                            .id(item.id)
                        }
                    }
                    .padding(8 * uiScale)
                }
                .onChange(of: model.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        centeredMessage(
            icon: "tray",
            title: "No clipboard history yet",
            subtitle: "Copy something to get started"
        )
    }

    private var noMatchesState: some View {
        centeredMessage(
            icon: "magnifyingglass",
            title: "No matches",
            subtitle: "Try a different search"
        )
    }

    private func centeredMessage(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10 * uiScale) {
            Image(systemName: icon)
                .font(.system(size: 38 * uiScale, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 16 * uiScale))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 12 * uiScale))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(role: .destructive) {
                history.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(history.items.isEmpty)

            Spacer()

            Text("⌃N / ⌃P to navigate · ↩ to copy")
                .font(.system(size: 10 * uiScale))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 16 * uiScale)
        .padding(.vertical, 11 * uiScale)
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let item: ClipItem
    let isSelected: Bool
    let onTap: () -> Void

    @State private var hovering = false

    private var highlighted: Bool { hovering || isSelected }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 11 * uiScale) {
                sourceIcon
                    .padding(.top, 1 * uiScale)

                VStack(alignment: .leading, spacing: 3 * uiScale) {
                    contentPreview
                    Text(subtitle)
                        .font(.system(size: 11 * uiScale))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11 * uiScale))
                    .foregroundStyle(.secondary)
                    .opacity(highlighted ? 1 : 0)
            }
            .padding(.horizontal, 12 * uiScale)
            .padding(.vertical, 9 * uiScale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9 * uiScale, style: .continuous)
                    .fill(.tint.opacity(isSelected ? 0.25 : (hovering ? 0.18 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            withAnimation(.easeOut(duration: 0.12)) { hovering = isHovered }
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let appIcon = item.sourceAppIcon {
            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16 * uiScale, height: 16 * uiScale)
                .clipShape(RoundedRectangle(cornerRadius: 3 * uiScale, style: .continuous))
        } else {
            Image(systemName: fallbackIcon)
                .font(.system(size: 12 * uiScale))
                .foregroundStyle(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 16 * uiScale)
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.content {
        case .text(let text):
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13 * uiScale))
                .lineLimit(3)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
        case .image(let img):
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 80 * uiScale)
                .cornerRadius(4 * uiScale)
        case .fileURLs(let urls):
            VStack(alignment: .leading, spacing: 2 * uiScale) {
                ForEach(urls.prefix(3), id: \.self) { url in
                    Text(url.lastPathComponent)
                        .font(.system(size: 13 * uiScale))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)
                }
                if urls.count > 3 {
                    Text("+ \(urls.count - 3) more")
                        .font(.system(size: 11 * uiScale))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var fallbackIcon: String {
        switch item.content {
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return "link" }
            return "text.alignleft"
        case .image:
            return "photo"
        case .fileURLs(let urls):
            return urls.count == 1 ? "doc" : "doc.on.doc"
        }
    }

    private var subtitle: String {
        let time = Self.relativeFormatter.localizedString(for: item.date, relativeTo: Date())
        let appSuffix = item.sourceAppName.map { " · \($0)" } ?? ""
        switch item.content {
        case .text(let text):
            let charCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
            return "\(charCount) char\(charCount == 1 ? "" : "s") · \(time)\(appSuffix)"
        case .image:
            return "Image · \(time)\(appSuffix)"
        case .fileURLs(let urls):
            let fileCount = urls.count
            return "\(fileCount) file\(fileCount == 1 ? "" : "s") · \(time)\(appSuffix)"
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
