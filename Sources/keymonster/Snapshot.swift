import SwiftUI
import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "snapshot")

/// Headless rendering of the history panel for autonomous design iteration.
///
/// Invoked via `keymonster snapshot [--out DIR] [--count N]`. It loads the real
/// on-disk history, then renders `MenuContent` at successive selection indices
/// into an offscreen window and writes one PNG per selection state. No global
/// hotkey, status-item click, screen-recording permission, or synthetic key
/// events are needed — the loop is: edit the view, run this, read the PNGs.
///
/// `keymonster snapshot --demo [--out DIR]` instead renders publishable
/// screenshots (for the website/README) from curated demo content seeded into an
/// in-memory store — the real on-disk history never touches these images.
@MainActor
enum SnapshotRunner {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        if CommandLine.arguments.contains("--demo") {
            runDemo()
            return
        }

        let outDir = option("--out") ?? (NSTemporaryDirectory() + "keymonster-snapshots")
        let count = option("--count").flatMap(Int.init) ?? 5
        let outURL = URL(fileURLWithPath: outDir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
        } catch {
            fail("could not create output dir \(outDir): \(error)")
        }

        // Read the same database the app writes to.
        let history = ClipboardHistory()
        do {
            history.configure(store: try SQLiteClipStore(url: SQLiteClipStore.defaultURL()))
        } catch {
            fail("could not open history store: \(error)")
        }

        let items = history.items
        guard !items.isEmpty else {
            fail("history is empty — run the app and copy a few things first")
        }

        let model = HistoryViewModel(history: history)
        model.prepareForPresentation()

        let window = makeWindow()
        let hosting = NSHostingView(rootView: MenuContent(history: history, model: model))
        hosting.frame = NSRect(origin: .zero, size: window.frame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.orderFront(nil)

        let shots = min(count, items.count)
        var written: [String] = []
        for index in 0..<shots {
            model.selectedID = items[index].id
            settle(0.35)  // let SwiftUI commit layout + the scroll-to-selection animation
            let url = outURL.appendingPathComponent(String(format: "history-%02d.png", index))
            if capture(window, to: url) { written.append(url.path) }
        }

        for path in written { print(path) }
        log.info("wrote \(written.count) snapshot(s) to \(outDir)")
        exit(written.isEmpty ? 1 : 0)
    }

    // MARK: - Rendering

    /// A borderless, transparent window matching the live panel's size so the
    /// view's own rounded material and corners render as they do in the app.
    /// Positioned offscreen so nothing flashes on the user's display.
    private static func makeWindow(
        size: NSSize = NSSize(width: 620 * uiScale, height: 500 * uiScale)
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        return window
    }

    private static func capture(_ window: NSWindow, to url: URL) -> Bool {
        guard let view = window.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            log.error("no bitmap rep for \(url.lastPathComponent)")
            return false
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            log.error("png encode failed for \(url.lastPathComponent)")
            return false
        }
        do {
            try data.write(to: url)
            return true
        } catch {
            log.error("write failed for \(url.lastPathComponent): \(error)")
            return false
        }
    }

    /// Pump the main run loop so SwiftUI's update/layout cycle runs between
    /// selection changes (we never call `NSApplication.run()`).
    private static func settle(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    // MARK: - Demo shots (website / README)

    /// Renders the history panel and menu-finder panel against seeded demo
    /// content, in dark and light appearance, and writes named PNGs. Everything
    /// shown is fabricated here — safe to publish.
    private static func runDemo() {
        let outDir = option("--out") ?? (NSTemporaryDirectory() + "keymonster-demo-shots")
        let outURL = URL(fileURLWithPath: outDir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
        } catch {
            fail("could not create output dir \(outDir): \(error)")
        }

        let history = ClipboardHistory()
        do {
            history.configure(store: try SQLiteClipStore.inMemory())
        } catch {
            fail("could not open in-memory store: \(error)")
        }
        seedDemoHistory(into: history)

        var written: [String] = []
        let appearances: [(suffix: String, name: NSAppearance.Name)] = [
            ("dark", .darkAqua), ("light", .aqua)
        ]
        for (suffix, appearanceName) in appearances {
            NSApp.appearance = NSAppearance(named: appearanceName)
            written += demoHistoryShots(history: history, outURL: outURL, suffix: suffix)
            written += demoMenuFinderShots(outURL: outURL, suffix: suffix)
        }

        for path in written { print(path) }
        log.info("wrote \(written.count) demo shot(s) to \(outDir)")
        exit(written.isEmpty ? 1 : 0)
    }

    private static func demoHistoryShots(
        history: ClipboardHistory, outURL: URL, suffix: String
    ) -> [String] {
        let model = HistoryViewModel(history: history)
        model.prepareForPresentation()

        let window = makeWindow()
        let hosting = NSHostingView(rootView: MenuContent(history: history, model: model))
        hosting.frame = NSRect(origin: .zero, size: window.frame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let items = history.items
        // Let the first render finish before touching the selection: the search
        // field's initial focus writes the binding back, and that didSet
        // re-selects the first item — anything set earlier would be undone.
        settle(0.5)

        func select(where predicate: (ClipItem) -> Bool) {
            model.selectedID = items.first(where: predicate)?.id ?? items.first?.id
        }

        var written: [String] = []
        func shot(_ name: String) {
            settle(0.35)
            let url = outURL.appendingPathComponent("\(name)-\(suffix).png")
            if capture(window, to: url) { written.append(url.path) }
        }

        // The multi-line code snippet, so the preview pane is full.
        select { if case .text(let text) = $0.content { return text.contains("func matches") }
                 return false }
        shot("clipboard-text")

        select { if case .image = $0.content { return true } else { return false } }
        shot("clipboard-image")

        model.searchText = "monster"
        shot("clipboard-search")
        model.searchText = ""

        return written
    }

    private static func demoMenuFinderShots(outURL: URL, suffix: String) -> [String] {
        let model = MenuFinderViewModel()
        model.present(items: demoMenuItems(), appName: "Safari")
        model.searchText = "re"

        let size = NSSize(width: 540 * uiScale, height: 460 * uiScale)
        let window = makeWindow(size: size)
        let hosting = NSHostingView(rootView: MenuFinderContent(model: model))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        settle(0.35)
        let url = outURL.appendingPathComponent("menu-search-\(suffix).png")
        return capture(window, to: url) ? [url.path] : []
    }

    // MARK: - Demo content

    /// Seeds plausible, entirely made-up clipboard traffic. Ordered oldest first
    /// so the panel lists them newest-on-top in this reverse order.
    private static func seedDemoHistory(into history: ClipboardHistory) {
        let finder = ("Finder", "com.apple.finder")
        let safari = ("Safari", "com.apple.Safari")
        let terminal = ("Terminal", "com.apple.Terminal")
        let notes = ("Notes", "com.apple.Notes")
        let preview = ("Preview", "com.apple.Preview")
        let messages = ("Messages", "com.apple.MobileSMS")
        let textEdit = ("TextEdit", "com.apple.TextEdit")
        let mail = ("Mail", "com.apple.mail")

        func add(_ content: ClipContent, from app: (String, String)) {
            history.add(content, sourceAppName: app.0, sourceAppBundleID: app.1)
        }

        add(.fileURLs([
            URL(fileURLWithPath: "/Users/robin/Screenshots/panel-hero.png"),
            URL(fileURLWithPath: "/Users/robin/Screenshots/grid-loupe.png")
        ]), from: finder)
        add(.text(
            "Draft: the monster now lives in the menu bar and answers to a single chord. Copy anything — it remembers."
        ), from: mail)
        add(.text("#45b3f0 → #1868b6 (fur gradient), #131c26 (mouth)"), from: notes)
        add(.text("https://en.wikipedia.org/wiki/Clipboard_(computing)"), from: safari)
        if let image = demoImageData() {
            add(.image(image), from: preview)
        }
        add(.text("shipped the grid loupe 🔍 small targets don't stand a chance"), from: messages)
        add(.text("""
        func matches(lowercasedQuery query: String) -> Bool {
            if let name = sourceAppName?.lowercased(),
               name.contains(query) { return true }
            switch content {
            case .text(let text):
                return text.lowercased().contains(query)
            case .image:
                return false
            case .fileURLs(let urls):
                return urls.contains {
                    $0.lastPathComponent.lowercased().contains(query)
                }
            }
        }
        """), from: textEdit)
        add(.fileURLs([URL(fileURLWithPath: "/Users/robin/Notes/keymonster-launch.md")]), from: finder)
        add(.text("https://github.com/semanticart/keymonster"), from: safari)
        add(.text("make install INSTALL_DIR=~/Applications"), from: terminal)
    }

    /// The app icon rendered to PNG data — the "copied image" in the demo feed.
    private static func demoImageData() -> Data? {
        let renderer = ImageRenderer(content: AppIconView().frame(width: 480, height: 480))
        renderer.scale = 2
        guard let tiff = renderer.nsImage?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func demoMenuItems() -> [MenuBarItem] {
        let entries: [(path: [String], title: String)] = [
            (["File"], "Export as PDF…"),
            (["File", "Share"], "Messages"),
            (["View"], "Reload Page"),
            (["View"], "Actual Size"),
            (["History"], "Reopen Last Closed Tab"),
            (["Develop"], "Show Web Inspector"),
            (["Develop"], "Empty Caches"),
            (["Window"], "Merge All Windows"),
            (["Bookmarks"], "Show Bookmarks"),
            (["File"], "Print…")
        ]
        return entries.enumerated().map { index, entry in
            MenuBarItem(id: index, path: entry.path, title: entry.title)
        }
    }

    // MARK: - Args

    private static func option(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("keymonster snapshot: \(message)\n".utf8))
        exit(1)
    }
}
