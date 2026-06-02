import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Global Shortcut")
                    Spacer()
                    ShortcutRecorder(shortcut: $settings.shortcut)
                }
            } footer: {
                Text("Opens clipboard history from anywhere.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding(.vertical)
    }
}

// MARK: - Recorder

private struct ShortcutRecorder: View {
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
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        // Temporarily unregister so the current hotkey doesn't fire while recording.
        // (HotkeyManager keeps its ref; we'll re-register in AppDelegate via settings change.)
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
        if let m = eventMonitor {
            NSEvent.removeMonitor(m)
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
