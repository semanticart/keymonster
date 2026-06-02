import SwiftUI
import AppKit

/// The dropdown shown from the menu-bar icon: a scrollable history list plus controls.
struct MenuContent: View {
    @ObservedObject var history: ClipboardHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if history.items.isEmpty {
                Text("No clipboard history yet.\nCopy something to get started.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(history.items) { item in
                            HistoryRow(item: item) { copyToPasteboard(item.text) }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }

            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Text("Clipboard History").font(.headline)
            Spacer()
            Text("\(history.items.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var footer: some View {
        HStack {
            Button("Clear") { history.clear() }
                .disabled(history.items.isEmpty)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(8)
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        // The watcher will see this write and move the item to the top (most-recently-used).
    }
}

private struct HistoryRow: View {
    let item: ClipItem
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(hovering ? Color.accentColor.opacity(0.15) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
    }
}
