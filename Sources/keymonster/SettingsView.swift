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
        if let hintLeft = settings.hintLeftShortcut { all.append(hintLeft) }
        if let hintRight = settings.hintRightShortcut { all.append(hintRight) }
        if let grid = settings.gridShortcut { all.append(grid) }
        if let textJump = settings.textJumpShortcut { all.append(textJump) }
        return ShortcutConflicts.conflicting(all)
    }

    private func isConflicting(_ shortcut: Shortcut?) -> Bool {
        guard let shortcut else { return false }
        return conflicts.contains(shortcut)
    }

    private var hintsConfigured: Bool {
        settings.hintLeftShortcut != nil || settings.hintRightShortcut != nil
    }

    var body: some View {
        Form {
            Section {
                ShortcutSettingRow(
                    title: "Clipboard Shortcut",
                    shortcut: $settings.shortcut,
                    isConflicting: isConflicting(settings.shortcut)
                )
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
                ShortcutSettingRow(
                    title: "Left Click",
                    shortcut: $settings.hintLeftShortcut,
                    isConflicting: isConflicting(settings.hintLeftShortcut)
                )
                ShortcutSettingRow(
                    title: "Right Click",
                    shortcut: $settings.hintRightShortcut,
                    isConflicting: isConflicting(settings.hintRightShortcut)
                )
                if hintsConfigured && !accessTrusted {
                    AccessibilityNotice()
                }
            } header: {
                Text("Click Hints")
            } footer: {
                Text("Overlay short labels on everything clickable in the active "
                    + "window — including web pages — and type one to click it. Hold "
                    + "Shift on the last letter for the opposite mouse button; Esc "
                    + "cancels. Requires Accessibility permission.")
                    .foregroundStyle(.secondary)
            }

            ShortcutSettingSection(
                title: "Show Grid",
                shortcut: $settings.gridShortcut,
                isConflicting: isConflicting(settings.gridShortcut),
                showAccessibilityNotice: settings.gridShortcut != nil && !accessTrusted,
                header: "Grid Click",
                footer: "Overlay a grid mirroring the keyboard's letter rows (Q–/) on the "
                    + "active window; each key zooms into that cell, and after two "
                    + "zooms the next key clicks. Return clicks the center anytime — "
                    + "hold Shift to right-click. Delete zooms back out; Esc cancels. "
                    + "Requires Accessibility permission."
            )

            ShortcutSettingSection(
                title: "Jump to Character",
                shortcut: $settings.textJumpShortcut,
                isConflicting: isConflicting(settings.textJumpShortcut),
                showAccessibilityNotice: settings.textJumpShortcut != nil && !accessTrusted,
                header: "Text Jump",
                footer: "In the active text field — native or web — press this shortcut, "
                    + "then a character. Every visible occurrence gets a label; type one "
                    + "to drop the caret just before that character. Delete picks a "
                    + "different character; Esc cancels. Requires Accessibility permission."
            )

            Section {
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            } footer: {
                Text("Start Key Monster automatically when you log in.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Paste into the active app on Return", isOn: $settings.autoPaste)
                if settings.autoPaste && !accessTrusted {
                    AccessibilityNotice()
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

/// Shown wherever a feature needing Accessibility permission is enabled but the app isn't trusted yet.
private struct AccessibilityNotice: View {
    var body: some View {
        HStack {
            Label("Accessibility access needed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Spacer()
            Button("Open Settings…") { Paster.openAccessibilitySettings() }
        }
    }
}

/// A titled shortcut recorder plus its conflict warning, shared by every single-shortcut settings row.
private struct ShortcutSettingRow: View {
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
private struct ShortcutSettingSection: View {
    let title: String
    @Binding var shortcut: Shortcut?
    let isConflicting: Bool
    let showAccessibilityNotice: Bool
    let header: String
    let footer: String

    var body: some View {
        Section {
            ShortcutSettingRow(title: title, shortcut: $shortcut, isConflicting: isConflicting)
            if showAccessibilityNotice {
                AccessibilityNotice()
            }
        } header: {
            Text(header)
        } footer: {
            Text(footer)
                .foregroundStyle(.secondary)
        }
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
