import SwiftUI
import AppKit

/// The menu-finder panel's contents: a header with the active app's name, a
/// search field, and a single-column list of that app's menu items ranked by the
/// query. Styled to match the history panel.
struct MenuFinderContent: View {
    @ObservedObject var model: MenuFinderViewModel

    var onClose: () -> Void = {}

    @FocusState private var searchFocused: Bool

    private static let width: CGFloat = 540 * uiScale
    private static let height: CGFloat = 460 * uiScale

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .frame(width: Self.width, height: Self.height)
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
                Image(systemName: "filemenu.and.selection")
                    .font(.system(size: 18 * uiScale))
                    .foregroundStyle(.tint)
                    .frame(width: 26 * uiScale, height: 26 * uiScale)

                VStack(alignment: .leading, spacing: 1 * uiScale) {
                    Text("Menu Search")
                        .font(.system(size: 17 * uiScale, weight: .semibold))
                    Text(model.appName.isEmpty ? "Active app" : model.appName)
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

            TextField("Search menus", text: $model.searchText)
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
        if model.items.isEmpty {
            emptyState
        } else if model.filteredItems.isEmpty {
            noMatchesState
        } else {
            list
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3 * uiScale) {
                    ForEach(model.filteredItems) { item in
                        MenuItemRow(item: item, isSelected: item.id == model.selectedID) {
                            model.selectedID = item.id
                        }
                        .id(item.id)
                    }
                }
                .padding(6 * uiScale)
            }
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Empty states

    private var emptyState: some View {
        centeredMessage(
            icon: "menubar.rectangle",
            title: "No menu items",
            subtitle: "This app didn't expose any menus"
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
            Spacer()
            Text("⌃N/P navigate · ↩ run")
                .font(.system(size: 10 * uiScale))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16 * uiScale)
        .padding(.vertical, 11 * uiScale)
    }
}

// MARK: - Row

private struct MenuItemRow: View {
    let item: MenuBarItem
    let isSelected: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6 * uiScale) {
                // The breadcrumb, with the leaf item emphasized over its path.
                Text(pathPrefix)
                    .foregroundStyle(.secondary)
                + Text(item.title)
                    .foregroundStyle(.primary)
            }
            .font(.system(size: 13 * uiScale))
            .lineLimit(1)
            .truncationMode(.middle)
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
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering }
        }
    }

    /// The ancestor path with a trailing separator, e.g. `"File › "`; empty for a
    /// top-level item.
    private var pathPrefix: String {
        item.path.isEmpty ? "" : item.path.joined(separator: " › ") + " › "
    }
}
