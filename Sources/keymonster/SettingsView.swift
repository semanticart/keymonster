import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var accessTrusted = Paster.isTrusted

    // Accessibility is granted in System Settings, out of our process, so there's
    // no event to observe. Poll while the window is open; macOS updates the trust
    // value live, so the warning clears on its own once the user flips the switch.
    private let trustPoll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Key combos bound more than once across every shortcut. Only the first
    /// registration of a duplicate actually works.
    private var conflicts: Set<Shortcut> {
        let singles = [
            settings.shortcut, settings.hintLeftShortcut, settings.hintRightShortcut,
            settings.gridShortcut, settings.textJumpShortcut, settings.menuSearchShortcut
        ]
        return ShortcutConflicts.conflicting(
            singles.compactMap { $0 }
                + settings.appShortcuts.compactMap(\.shortcut)
                + settings.scriptShortcuts.compactMap(\.shortcut)
        )
    }

    private func isConflicting(_ shortcut: Shortcut?) -> Bool {
        guard let shortcut else { return false }
        return conflicts.contains(shortcut)
    }

    private var hintsConfigured: Bool {
        settings.hintLeftShortcut != nil || settings.hintRightShortcut != nil
    }

    // General (the app's identity, no shortcuts) leads; the shortcut tabs then
    // run clipboard core first, mouse-replacement features roughly in how often
    // they fire, then automation. applyHotkeys registers shortcuts in that same
    // tab order, which matters when two entries share a combo.
    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            clipboardTab
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
            focusTab
                .tabItem { Label("Focus", systemImage: "macwindow.on.rectangle") }
            clickingTab
                .tabItem { Label("Clicking", systemImage: "cursorarrow.rays") }
            textTab
                .tabItem { Label("Text", systemImage: "character.cursor.ibeam") }
            menusTab
                .tabItem { Label("Menus", systemImage: "filemenu.and.selection") }
            scriptsTab
                .tabItem { Label("Scripts", systemImage: "terminal") }
        }
        // Width is fixed; height comes from the selected tab's content. The
        // hand-rolled SettingsSection cards (not List-backed Form) make each
        // tab report its natural height, and AppDelegate resizes the window to
        // follow it.
        .frame(width: 540)
        .onChange(of: settings.autoPaste) { _, enabled in
            if enabled { Paster.requestAccess() }
            accessTrusted = Paster.isTrusted
        }
        .onReceive(trustPoll) { _ in
            accessTrusted = Paster.isTrusted
        }
    }

    // MARK: - Tabs

    private var clipboardTab: some View {
        SettingsTabView(description: "Key Monster records what you copy — text, images, "
            + "and files — and keeps it searchable. Summon the history panel from anywhere, "
            + "type to filter, and press Return to paste an earlier item.") {
            SettingsSection(footer: "Opens clipboard history from anywhere.") {
                ShortcutSettingRow(
                    title: "Clipboard Shortcut",
                    shortcut: $settings.shortcut,
                    isConflicting: isConflicting(settings.shortcut)
                )
            }

            SettingsSection(footer: "Pastes the selected item straight into the app you "
                + "were using. Requires Accessibility permission; without it, Return "
                + "just copies.") {
                SettingsToggleRow(title: "Paste into the active app on Return", isOn: $settings.autoPaste)
                if settings.autoPaste && !accessTrusted {
                    AccessibilityNotice()
                }
            }
        }
    }

    private var focusTab: some View {
        SettingsTabView(description: "Switch apps without Cmd-Tab. Bind a shortcut to one "
            + "or more apps: press it to focus the first, press again to cycle through the "
            + "rest — so one combo can rotate through e.g. Slack and Chrome.") {
            SettingsSection {
                ForEach($settings.appShortcuts) { $entry in
                    FocusShortcutRow(entry: $entry, isConflicting: isConflicting(entry.shortcut)) {
                        settings.appShortcuts.removeAll { $0.id == entry.id }
                    }
                    Divider()
                }
                Button {
                    settings.appShortcuts.append(AppShortcut())
                } label: {
                    Label("Add Shortcut", systemImage: "plus")
                }
            }
        }
    }

    private var clickingTab: some View {
        SettingsTabView(description: "Click anything on screen without touching the mouse: "
            + "hints label everything clickable, and the grid reaches spots that have no "
            + "element to label. Both require Accessibility permission.") {
            SettingsSection(
                header: "Click Hints",
                footer: "Overlay short labels on everything clickable in the active "
                    + "window — including web pages — and type one to click it. Hold "
                    + "Shift on the last letter for the opposite mouse button; Esc "
                    + "cancels."
            ) {
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
            }

            SettingsSection(
                header: "Grid Click",
                footer: "Overlay a grid mirroring the keyboard's letter rows (Q–/) on the "
                    + "active window; each key zooms into that cell, and after two "
                    + "zooms the next key clicks. Return clicks the center anytime — "
                    + "hold Shift to right-click. Delete zooms back out; Esc cancels."
            ) {
                ShortcutSettingRow(
                    title: "Show Grid",
                    shortcut: $settings.gridShortcut,
                    isConflicting: isConflicting(settings.gridShortcut)
                )
                if settings.gridShortcut != nil && !accessTrusted {
                    AccessibilityNotice()
                }
            }
        }
    }

    private var textTab: some View {
        SettingsTabView(description: "Move the caret through text by sight instead of "
            + "arrow keys. Requires Accessibility permission.") {
            ShortcutSettingSection(
                title: "Jump to Character",
                shortcut: $settings.textJumpShortcut,
                isConflicting: isConflicting(settings.textJumpShortcut),
                showAccessibilityNotice: settings.textJumpShortcut != nil && !accessTrusted,
                header: "Text Jump",
                footer: "In the active text field — native or web — press this shortcut, "
                    + "then a character. Every visible occurrence gets a label; type one "
                    + "to drop the caret just before that character. Delete picks a "
                    + "different character; Esc cancels."
            )
        }
    }

    private var menusTab: some View {
        SettingsTabView(description: "Run any menu bar item by typing a few letters "
            + "instead of hunting through menus. Requires Accessibility permission.") {
            ShortcutSettingSection(
                title: "Search Menus",
                shortcut: $settings.menuSearchShortcut,
                isConflicting: isConflicting(settings.menuSearchShortcut),
                showAccessibilityNotice: settings.menuSearchShortcut != nil && !accessTrusted,
                header: "Menu Search",
                footer: "List the active app's menu bar items in a searchable panel. "
                    + "Type to fuzzy-find, use ↑/↓ or Ctrl-N/Ctrl-P to move, and press "
                    + "Return to run the highlighted item. Esc cancels."
            )
        }
    }

    private var scriptsTab: some View {
        SettingsTabView(description: "Run your own automation from a keystroke. Point a "
            + "shortcut at a script file: AppleScript (.scpt, .applescript) runs via "
            + "osascript, executables run directly (their shebang picks the interpreter), "
            + "and anything else runs in zsh as a login shell, so your usual PATH applies.") {
            ScriptShortcutsSection(settings: settings, isConflicting: isConflicting)
        }
    }

    private var generalTab: some View {
        SettingsTabView(description: "A keyboard-driven clipboard history — plus keyboard-"
            + "only ways to focus apps, click anything, jump through text, search menus, "
            + "and run scripts. Each tab configures one feature.") {
            VStack(spacing: 6) {
                AppIconView()
                    .frame(width: 80, height: 80)
                Text("Key Monster")
                    .font(.title3.weight(.semibold))
                Text("by Jeffrey Chupp")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            SettingsSection(footer: "Start Key Monster automatically when you log in.") {
                SettingsToggleRow(title: "Launch at Login", isOn: $settings.launchAtLogin)
            }
        }
    }
}

/// One Settings tab: a description of the feature up top, then its sections.
/// A plain VStack (no Form, no scrolling) so the tab's ideal height is its
/// content height and the window can size to it.
private struct SettingsTabView<Content: View>: View {
    let description: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(description)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            content
        }
        .padding(20)
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
