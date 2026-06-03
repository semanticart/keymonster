import SwiftUI
import AppKit
import os.log

private let log = Logger(subsystem: "clipborg", category: "snapshot")

/// Headless rendering of the history panel for autonomous design iteration.
///
/// Invoked via `clipborg snapshot [--out DIR] [--count N]`. It loads the real
/// on-disk history, then renders `MenuContent` at successive selection indices
/// into an offscreen window and writes one PNG per selection state. No global
/// hotkey, status-item click, screen-recording permission, or synthetic key
/// events are needed — the loop is: edit the view, run this, read the PNGs.
@MainActor
enum SnapshotRunner {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let outDir = option("--out") ?? (NSTemporaryDirectory() + "clipborg-snapshots")
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
    private static func makeWindow() -> NSWindow {
        let size = NSSize(width: 620 * uiScale, height: 500 * uiScale)
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

    // MARK: - Args

    private static func option(_ name: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("clipborg snapshot: \(message)\n".utf8))
        exit(1)
    }
}
