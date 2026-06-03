import SwiftUI
import AppKit
import os.log

private let log = Logger(subsystem: "clipborg", category: "menu")

/// The centered panel's contents: a full-width header with search, a split
/// content area (left list + right detail), and a full-width footer.
struct MenuContent: View {
    @ObservedObject var history: ClipboardHistory
    @ObservedObject var model: HistoryViewModel

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
        .frame(width: 620 * uiScale, height: 500 * uiScale)
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
            HStack(spacing: 0) {
                leftPanel
                Divider().opacity(0.4)
                rightPanel
            }
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3 * uiScale) {
                    ForEach(model.filteredItems) { item in
                        CompactHistoryRow(
                            item: item,
                            isSelected: item.id == model.selectedID
                        ) {
                            copyToPasteboard(item)
                            onClose()
                        }
                        .id(item.id)
                    }
                }
                .padding(6 * uiScale)
            }
            .frame(width: 200 * uiScale)
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Right Panel

    @ViewBuilder
    private var rightPanel: some View {
        if let item = model.selectedItem {
            DetailScrollHost(item: item, viewModel: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("Select an item")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Empty States

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

            Text("⌃N/P navigate · ⌃J/K scroll · ↩ copy")
                .font(.system(size: 10 * uiScale))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 16 * uiScale)
        .padding(.vertical, 11 * uiScale)
    }
}

// MARK: - Compact Row (left panel)

private struct CompactHistoryRow: View {
    let item: ClipItem
    let isSelected: Bool
    let onTap: () -> Void

    @State private var hovering = false
    private var highlighted: Bool { hovering || isSelected }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8 * uiScale) {
                sourceIcon
                Text(descriptor)
                    .font(.system(size: 12 * uiScale))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 9 * uiScale)
            .padding(.vertical, 7 * uiScale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7 * uiScale, style: .continuous)
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

    private var descriptor: String {
        switch item.content {
        case .text(let text):
            let firstLine = text.components(separatedBy: .newlines)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? text
            return firstLine.trimmingCharacters(in: .whitespaces)
        case .image:
            return "Image"
        case .fileURLs(let urls):
            return urls.count == 1
                ? urls[0].lastPathComponent
                : urls.map { $0.lastPathComponent }.joined(separator: ", ")
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
}
