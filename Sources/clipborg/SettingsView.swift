import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var accessTrusted = Paster.isTrusted

    // Accessibility is granted in System Settings, out of our process, so there's
    // no event to observe. Poll while the window is open; macOS updates the trust
    // value live, so the warning clears on its own once the user flips the switch.
    private let trustPoll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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

            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            } footer: {
                Text("Start Clipborg automatically when you log in.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Paste into the active app on Return", isOn: $settings.autoPaste)
                if settings.autoPaste && !accessTrusted {
                    HStack {
                        Label("Accessibility access needed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Settings…") { Paster.openAccessibilitySettings() }
                    }
                }
            } footer: {
                Text("Pastes the selected item straight into the app you were using. "
                    + "Requires Accessibility permission; without it, Return just copies.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding(.vertical)
        .onChange(of: settings.autoPaste) { _, enabled in
            if enabled { Paster.requestAccess() }
            accessTrusted = Paster.isTrusted
        }
        .onReceive(trustPoll) { _ in
            accessTrusted = Paster.isTrusted
        }
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
        if isRecording { stopRecording() } else { startRecording() }
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
