import AppKit

/// AppKit-facing pieces split out of ClipboardHistory.swift so the model types
/// (`ClipContent`, `ClipItem`, `ClipboardHistory`) stay headless: no `NSImage`,
/// no `NSRunningApplication`, cheap `Data` equality on the dedup path.

/// Bundle-ID-keyed app icon cache. `NSWorkspace` app resolution isn't free, so
/// the view layer resolves icons here at render time instead of storing an
/// `NSImage` on every `ClipItem`.
@MainActor
private var iconCache: [String: NSImage] = [:]

@MainActor
func iconForBundleID(_ bundleID: String?) -> NSImage? {
    guard let id = bundleID else { return nil }
    if let cached = iconCache[id] { return cached }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    iconCache[id] = icon
    return icon
}

/// Writes a clip's content onto the general pasteboard. The watcher will see the
/// write and move the item to the top (most-recently-used).
@MainActor
func copyToPasteboard(_ item: ClipItem) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    switch item.content {
    case .text(let text):
        pasteboard.setString(text, forType: .string)
        if let data = item.richTextData, let typeStr = item.richTextType {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(rawValue: typeStr))
        }
    case .image(let data):
        if let image = NSImage(data: data) {
            pasteboard.writeObjects([image])
        }
    case .fileURLs(let urls):
        pasteboard.writeObjects(urls as [NSURL])
    }
}

extension ClipboardHistory {
    /// Thin AppKit-facing convenience for callers holding an `NSRunningApplication`
    /// (the watcher) so the core `add(_:sourceAppName:sourceAppBundleID:...)` stays
    /// headless. `sourceApp` has no default, so calls that omit it resolve to the
    /// headless overload instead of this one.
    func add(
        _ content: ClipContent,
        sourceApp: NSRunningApplication?,
        richTextData: Data? = nil,
        richTextType: String? = nil
    ) {
        add(
            content,
            sourceAppName: sourceApp?.localizedName,
            sourceAppBundleID: sourceApp?.bundleIdentifier,
            richTextData: richTextData,
            richTextType: richTextType
        )
    }
}
