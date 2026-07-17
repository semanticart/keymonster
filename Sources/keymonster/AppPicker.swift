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

    @MainActor
    static func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
