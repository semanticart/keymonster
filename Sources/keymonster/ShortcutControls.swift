import SwiftUI
import AppKit

// Reusable building blocks for the Settings form: the shortcut recorder button,
// the conflict/Accessibility notices, and the standard single-shortcut row and
// section shapes built from them.

// MARK: - Recorder

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                Text(label)
                    .monospacedDigit()
                    .frame(minWidth: 110, alignment: .center)
            }
            .keyboardShortcut(.defaultAction) // suppress default button behavior
            .buttonStyle(RecorderButtonStyle(isRecording: isRecording))

            if shortcut != nil && !isRecording {
                Button {
                    stopRecording()
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording { return "Type a shortcut…" }
        return shortcut?.displayString ?? "Record Shortcut"
    }

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        // Suspend all global hotkeys while recording: AppSettings.shared.suspendHotkeys
        // makes AppDelegate.applyHotkeys register an empty binding list (it re-runs via
        // the objectWillChange subscription), so a combo captured here can't also fire
        // as a live shortcut mid-recording.
        AppSettings.shared.suspendHotkeys = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape cancels
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard !flags.isEmpty else { return event }
            shortcut = Shortcut(keyCode: UInt32(event.keyCode), carbonModifiers: carbonModifiers(from: flags))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        AppSettings.shared.suspendHotkeys = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

private struct RecorderButtonStyle: ButtonStyle {
    let isRecording: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording ? Color.accentColor.opacity(0.12) : Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isRecording ? Color.accentColor : Color(.separatorColor),
                                lineWidth: 1
                            )
                    )
            )
    }
}

// MARK: - Notices

struct ConflictWarning: View {
    var body: some View {
        Label("This shortcut is used more than once; only one binding will work.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

/// Shown wherever a feature needing Accessibility permission is enabled but the app isn't trusted yet.
struct AccessibilityNotice: View {
    var body: some View {
        HStack {
            Label("Accessibility access needed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Spacer()
            Button("Open Settings…") { Paster.openAccessibilitySettings() }
        }
    }
}

// MARK: - Standard row/section shapes

/// A grouped-form-style section: optional header above, a rounded card of rows,
/// optional footer below. Hand-rolled instead of Form/.formStyle(.grouped)
/// because that is List-backed and never hugs its content height — with this,
/// each Settings tab reports its natural size and the window can auto-size.
struct SettingsSection<Content: View>: View {
    var header: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header)
                    .font(.subheadline.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(.separatorColor), lineWidth: 1)
                    )
            )
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A switch pinned to the row's trailing edge, like grouped-form toggles.
struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// A titled shortcut recorder plus its conflict warning, shared by every single-shortcut settings row.
struct ShortcutSettingRow: View {
    let title: String
    @Binding var shortcut: Shortcut?
    let isConflicting: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            ShortcutRecorder(shortcut: $shortcut)
        }
        if isConflicting {
            ConflictWarning()
        }
    }
}

/// A full settings section built around one `ShortcutSettingRow`, with an
/// optional Accessibility notice and header/footer text. Covers the Grid Click
/// and Text Jump sections, which are otherwise identical in shape.
struct ShortcutSettingSection: View {
    let title: String
    @Binding var shortcut: Shortcut?
    let isConflicting: Bool
    let showAccessibilityNotice: Bool
    let header: String
    let footer: String

    var body: some View {
        SettingsSection(header: header, footer: footer) {
            ShortcutSettingRow(title: title, shortcut: $shortcut, isConflicting: isConflicting)
            if showAccessibilityNotice {
                AccessibilityNotice()
            }
        }
    }
}
