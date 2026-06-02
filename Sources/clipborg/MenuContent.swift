import SwiftUI
import AppKit

/// The centered panel's contents: a header, a scrollable history list, and a
/// footer with Clear / Quit. Rendered on a rounded translucent material.
struct MenuContent: View {
    @ObservedObject var history: ClipboardHistory

    /// Called after the user picks an item (or quits) so the panel can dismiss.
    var onClose: () -> Void = {}

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
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10 * uiScale) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 16 * uiScale, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1 * uiScale) {
                Text("Clipboard History")
                    .font(.system(size: 17 * uiScale, weight: .semibold))
                Text(history.items.isEmpty ? "Empty" : "\(history.items.count) item\(history.items.count == 1 ? "" : "s")")
                    .font(.system(size: 12 * uiScale))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 18 * uiScale)
        .padding(.vertical, 14 * uiScale)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if history.items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 4 * uiScale) {
                    ForEach(history.items) { item in
                        HistoryRow(item: item) {
                            copyToPasteboard(item.content)
                            onClose()
                        }
                    }
                }
                .padding(8 * uiScale)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10 * uiScale) {
            Image(systemName: "tray")
                .font(.system(size: 38 * uiScale, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No clipboard history yet")
                .font(.system(size: 16 * uiScale))
                .foregroundStyle(.secondary)
            Text("Copy something to get started")
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

            Button {
                onClose()
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 16 * uiScale)
        .padding(.vertical, 11 * uiScale)
    }

    private func copyToPasteboard(_ content: ClipContent) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch content {
        case .text(let s):
            pb.setString(s, forType: .string)
        case .image(let img):
            pb.writeObjects([img])
        case .fileURLs(let urls):
            pb.writeObjects(urls as [NSURL])
        }
        // The watcher will see this write and move the item to the top (most-recently-used).
    }
}

// MARK: - Row

private struct HistoryRow: View {
    let item: ClipItem
    let onTap: () -> Void

    @State private var hovering = false

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
                    .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 12 * uiScale)
            .padding(.vertical, 9 * uiScale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9 * uiScale, style: .continuous)
                    .fill(.tint.opacity(hovering ? 0.18 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hovering = h }
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
                .foregroundStyle(hovering ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 16 * uiScale)
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.content {
        case .text(let s):
            Text(s.trimmingCharacters(in: .whitespacesAndNewlines))
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
        case .text(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t.hasPrefix("http://") || t.hasPrefix("https://") { return "link" }
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
        case .text(let s):
            let count = s.trimmingCharacters(in: .whitespacesAndNewlines).count
            return "\(count) char\(count == 1 ? "" : "s") · \(time)\(appSuffix)"
        case .image:
            return "Image · \(time)\(appSuffix)"
        case .fileURLs(let urls):
            let n = urls.count
            return "\(n) file\(n == 1 ? "" : "s") · \(time)\(appSuffix)"
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
