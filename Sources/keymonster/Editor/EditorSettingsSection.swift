import SwiftUI
import AppKit

/// The Text tab's Edit in Editor section: the shortcut, the editor command
/// (blank to fall back to the shell's variables), the terminal app for
/// editors that need one, and the latest failure when there is one.
struct EditorSettingsSection: View {
    @ObservedObject var settings: AppSettings
    let isConflicting: Bool
    let showAccessibilityNotice: Bool
    @ObservedObject private var scriptLog = ScriptLog.shared

    private var lastEditorFailure: ScriptLog.Failure? {
        guard let failure = scriptLog.lastFailure,
              failure.script == ExternalEditorController.logName else { return nil }
        return failure
    }

    var body: some View {
        SettingsSection(
            header: "Edit in Editor",
            footer: "Opens the active text field's contents in your editor, the way git "
                + "opens a commit message. Save and quit to put the edited text back; a "
                + "non-zero exit (:cq in vim) leaves the field as it was. Leave Editor "
                + "blank to use $\(EditorCommand.environmentVariable), $VISUAL, or $EDITOR from "
                + "your login shell. GUI editors must block until the file is closed, e.g. "
                + "code --wait. Terminal editors such as vim need a terminal to run in: "
                + "choose one below. Terminal, iTerm2, kitty, WezTerm, Alacritty, and "
                + "Ghostty each get a new window; any other app is handed a .command file."
        ) {
            ShortcutSettingRow(
                title: "Edit in Editor",
                shortcut: $settings.editInEditorShortcut,
                isConflicting: isConflicting
            )

            HStack {
                Text("Editor")
                Spacer()
                TextField("$\(EditorCommand.environmentVariable), $VISUAL, or $EDITOR",
                          text: $settings.editorCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(width: 260)
            }

            HStack(spacing: 6) {
                Text("Terminal")
                Spacer()
                if let terminal = settings.editorTerminal {
                    if let icon = AppPicker.icon(for: terminal.bundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(terminal.name)
                    Button("Change…", action: chooseTerminal)
                    Button {
                        settings.editorTerminal = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Run the editor directly instead of in a terminal")
                } else {
                    Text("None — the editor opens its own window")
                        .foregroundStyle(.secondary)
                    Button("Choose…", action: chooseTerminal)
                }
            }

            if showAccessibilityNotice {
                AccessibilityNotice()
            }
            if let failure = lastEditorFailure {
                ScriptFailureNotice(failure: failure)
            }
        }
    }

    private func chooseTerminal() {
        if let app = AppPicker.choose(message: "Choose the terminal app to run your editor in") {
            settings.editorTerminal = app
        }
    }
}
