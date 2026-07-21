import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// AppKit bridges for picking and displaying applications, used by the focus
/// shortcut editor in Settings.
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

    /// Present an open panel for choosing a script file to bind to a shortcut.
    /// Any file is allowed — scripts often have no extension — so the panel is
    /// unscoped. Returns the chosen path, or nil if the user cancels.
    @MainActor
    static func chooseScript() -> String? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Choose"
        panel.message = "Choose a script to run with this shortcut"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    @MainActor
    static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
