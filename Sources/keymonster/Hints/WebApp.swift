import AppKit

/// Recognizes Chromium/Electron apps, whose web-content accessibility tree is
/// built lazily and asynchronously (~2s) once an assistive client asks for it.
/// Hint mode uses this to know which apps to pre-warm and to keep retrying.
enum WebApp {
    @MainActor private static var cache: [String: Bool] = [:]

    @MainActor
    static func isWebBacked(_ app: NSRunningApplication) -> Bool {
        let key = app.bundleIdentifier ?? app.bundleURL?.path ?? "pid:\(app.processIdentifier)"
        if let hit = cache[key] { return hit }
        let result = isWebBacked(bundleID: app.bundleIdentifier, bundleURL: app.bundleURL)
        cache[key] = result
        return result
    }

    /// The pure core, so the classification is testable: a known Chromium
    /// browser by bundle id, or an app that ships an Electron/Chromium framework
    /// (Slack, VS Code, Discord, …).
    static func isWebBacked(bundleID: String?, bundleURL: URL?) -> Bool {
        if let bundleID, knownWebBundleIDs.contains(bundleID) { return true }
        guard let frameworks = bundleURL?.appendingPathComponent("Contents/Frameworks"),
              let names = try? FileManager.default.contentsOfDirectory(atPath: frameworks.path) else {
            return false
        }
        return names.contains { name in
            let lower = name.lowercased()
            return lower.contains("electron") || lower.contains("chromium")
        }
    }

    /// Chromium browsers whose framework is brand-named (so the framework scan
    /// wouldn't catch them) — matched by bundle id instead.
    static let knownWebBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta",
        "org.chromium.Chromium", "com.brave.Browser", "com.brave.Browser.beta",
        "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "company.thebrowser.Browser"
    ]
}
