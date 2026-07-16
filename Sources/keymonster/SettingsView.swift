import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var accessTrusted = Paster.isTrusted

    // Accessibility is granted in System Settings, out of our process, so there's
    // no event to observe. Poll while the window is open; macOS updates the trust
    // value live, so the warning clears on its own once the user flips the switch.
    private let trustPoll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Key combos bound more than once across the history shortcut and every
    /// focus shortcut. Only the first registration of a duplicate actually works.
    private var conflicts: Set<Shortcut> {
        var all: [Shortcut] = []
        if let history = settings.shortcut { all.append(history) }
        all.append(contentsOf: settings.appShortcuts.compactMap(\.shortcut))
        return ShortcutConflicts.conflicting(all)
    }

    private func isConflicting(_ shortcut: Shortcut?) -> Bool {
        guard let shortcut else { return false }
        return conflicts.contains(shortcut)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Clipboard Shortcut")
                    Spacer()
                    ShortcutRecorder(shortcut: $settings.shortcut)
                }
                if isConflicting(settings.shortcut) {
                    ConflictWarning()
                }
            } footer: {
                Text("Opens clipboard history from anywhere.")
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach($settings.appShortcuts) { $entry in
                    FocusShortcutRow(entry: $entry, isConflicting: isConflicting(entry.shortcut)) {
                        settings.appShortcuts.removeAll { $0.id == entry.id }
                    }
                }
                Button {
                    settings.appShortcuts.append(AppShortcut())
                } label: {
                    Label("Add Shortcut", systemImage: "plus")
                }
            } header: {
                Text("Focus Shortcuts")
            } footer: {
                Text("Bind a shortcut to one or more apps. Press it to focus the app; "
                    + "press again to cycle through the rest.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            } footer: {
                Text("Start Key Monster automatically when you log in.")
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

// MARK: - Focus shortcut row

private struct FocusShortcutRow: View {
    @Binding var entry: AppShortcut
    let isConflicting: Bool
    let onRemove: () -> Void

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
                .help("Remove this shortcut")
            }

            if isConflicting {
                ConflictWarning()
            }

            if entry.apps.isEmpty {
                Text("No apps selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.apps) { app in
                    HStack(spacing: 6) {
                        if let icon = AppPicker.icon(for: app.bundleID) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text(app.name)
                        Spacer()
                        Button {
                            entry.apps.removeAll { $0.id == app.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button(action: addApp) {
                Label("Add App…", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func addApp() {
        guard let ref = AppPicker.choose() else { return }
        if !entry.apps.contains(ref) {
            entry.apps.append(ref)
        }
    }
}

private struct ConflictWarning: View {
    var body: some View {
        Label("This shortcut is used more than once; only one binding will work.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

/// AppKit bridges for picking and displaying applications.
enum AppPicker {
    /// Present an open panel scoped to applications and return the chosen app's
    /// bundle id + display name. nil if the user cancels or the bundle is unreadable.
    @MainActor
    static func choose() -> AppRef? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        panel.message = "Choose an app to focus with this shortcut"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return AppRef(bundleID: bundleID, name: name)
    }

    @MainActor
    static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
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
