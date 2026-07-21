import SwiftUI
import AppKit

/// The Scripts tab's form content: the shortcut→script-file rows, and the
/// notice + Open Log button shown after a script fails.
struct ScriptShortcutsSection: View {
    @ObservedObject var settings: AppSettings
    let isConflicting: (Shortcut?) -> Bool
    @ObservedObject private var scriptLog = ScriptLog.shared

    var body: some View {
        SettingsSection(footer: "Scripts run in the background with your home directory "
            + "as the working directory. Failures are written to "
            + "~/Library/Logs/keymonster/scripts.log. Drag a file from Finder "
            + "onto a row to change its script, or onto Add Script to create "
            + "a shortcut for it.") {
            ForEach($settings.scriptShortcuts) { $entry in
                ScriptShortcutRow(entry: $entry, isConflicting: isConflicting(entry.shortcut)) {
                    settings.scriptShortcuts.removeAll { $0.id == entry.id }
                }
                Divider()
            }
            AddScriptButton {
                settings.scriptShortcuts.append(contentsOf: $0)
            }
        }

        if let failure = scriptLog.lastFailure {
            SettingsSection {
                ScriptFailureNotice(failure: failure)
            }
        }
    }
}

/// The Add Script button, doubling as a drop target: script files dragged from
/// Finder become new shortcut entries; a plain click adds an empty one.
private struct AddScriptButton: View {
    let onAdd: ([ScriptShortcut]) -> Void
    @State private var isDropTargeted = false

    var body: some View {
        Button {
            onAdd([ScriptShortcut()])
        } label: {
            Label("Add Script", systemImage: "plus")
        }
        .dropDestination(for: URL.self) { urls, _ in
            let dropped = urls.filter(\.isFileURL).map { ScriptShortcut(path: $0.path) }
            guard !dropped.isEmpty else { return false }
            onAdd(dropped)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .dropHighlight(when: isDropTargeted)
    }
}

private struct ScriptShortcutRow: View {
    @Binding var entry: ScriptShortcut
    let isConflicting: Bool
    let onRemove: () -> Void
    @State private var isDropTargeted = false

    private var fileMissing: Bool {
        !entry.isEmpty
            && !FileManager.default.fileExists(atPath: (entry.path as NSString).expandingTildeInPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ShortcutRecorder(shortcut: $entry.shortcut)
                Spacer()
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove this script shortcut")
            }

            if isConflicting {
                ConflictWarning()
            }

            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                if entry.isEmpty {
                    Text("No script chosen")
                        .foregroundStyle(.secondary)
                } else {
                    Text((entry.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(entry.path)
                }
                Spacer()
                Button(entry.isEmpty ? "Choose Script…" : "Change…") {
                    if let path = AppPicker.chooseScript() {
                        entry.path = path
                    }
                }
            }

            if fileMissing {
                Label("Script file not found", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: \.isFileURL) else { return false }
            entry.path = url.path
            return true
        } isTargeted: { isDropTargeted = $0 }
        .dropHighlight(when: isDropTargeted)
    }
}

private extension View {
    /// Accent outline shown while a drag hovers over a drop target.
    func dropHighlight(when targeted: Bool) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: targeted ? 2 : 0)
                .padding(-4)
        )
    }
}

/// Shown after a script shortcut fails: what broke, and a way to the log file.
private struct ScriptFailureNotice: View {
    let failure: ScriptLog.Failure

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("\(failure.script) — \(failure.detail)",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(3)
            Spacer()
            Button("Open Log") { ScriptLog.shared.open() }
        }
    }
}
