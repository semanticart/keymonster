#if DEBUG
import AppKit
import Carbon.HIToolbox
import SwiftUI
import os.log

private let log = Logger(subsystem: "keymonster", category: "debug.secinput")

/// `keymonster secinput [once] [hold:<seconds>]` — a live monitor for Secure
/// Keyboard Entry (macOS's anti-keylogging state; see `SecureInput`). Prints a
/// line whenever the state flips so you can find what's blocking key taps on a
/// machine by elimination: leave it running and quit suspects one at a time
/// until it reports `off`.
///
/// Crucial caveat baked into the output: the "holder" from
/// `kCGSSessionSecureInputPID` is NOT the process that enabled secure input —
/// it's the app currently *receiving* secure input, i.e. the frontmost app, and
/// it changes as focus changes. So the named app is usually a red herring; trust
/// the on/off flag and the elimination, not the name. The line flags when the
/// reported holder is just the frontmost app (`==frontmost`, the misleading
/// case) versus a distinct background process (`background`, worth a look).
///
/// Modes:
///   (default)     monitor until Ctrl-C, printing on every change
///   once          print the current state once and exit
///   hold:<secs>   enable secure input from THIS process for <secs> (a self-test
///                 that confirms the monitor detects a known hold), then exit
///
/// Debug-only tooling. Reads no privileged state, so `swift run keymonster
/// secinput` works anywhere — no Accessibility grant or app bundle needed.
@MainActor
enum SecInputRunner {
    static func main() {
        // Unbuffered stdout: this streams for a long time and is usually piped to
        // a file or `tee`, where block buffering would swallow lines until exit.
        setbuf(stdout, nil)

        let args = CommandLine.arguments
        let rest = (args.firstIndex(of: "secinput")).map { Array(args[($0 + 1)...]) } ?? []

        if rest.first == "shot" {
            let dir = rest.count > 1 ? rest[1] : NSTemporaryDirectory() + "keymonster-secinput-shots"
            renderShots(into: dir)
            exit(0)
        }

        if rest.first == "banner" {
            let dir = rest.count > 1 ? rest[1] : NSTemporaryDirectory() + "keymonster-secinput-shots"
            renderBanners(into: dir)
            exit(0)
        }

        if rest.contains("once") {
            print(header)
            print("\(timestamp())  \(stateDescription())")
            print("permissions: Accessibility \(KeyTapAccess.accessibility.label) · "
                + "Input Monitoring \(KeyTapAccess.inputMonitoring.label)")
            exit(0)
        }

        if let holdArg = rest.first(where: { $0.hasPrefix("hold:") }),
           let seconds = Double(holdArg.dropFirst("hold:".count)) {
            fputs("secinput: enabling Secure Event Input for \(seconds)s (self-test)…\n", stderr)
            fputs("          note it names the FRONTMOST app, not this process — that's the point.\n\n", stderr)
            EnableSecureEventInput()
            print(header)
            monitor(until: Date().addingTimeInterval(seconds))
            DisableSecureEventInput()
            fputs("\nsecinput: released.\n", stderr)
            exit(0)
        }

        fputs("secinput: watching Secure Keyboard Entry — quit suspect apps one at a\n", stderr)
        fputs("          time and watch for `off`. Ctrl-C to stop.\n\n", stderr)
        print(header)
        monitor(until: nil)
    }

    /// Poll every 200ms; emit a line only when the state (ignoring the
    /// timestamp) changes. Runs until `deadline` (nil = forever).
    private static func monitor(until deadline: Date?) {
        var last = ""
        while deadline.map({ Date() < $0 }) ?? true {
            let description = stateDescription()
            if description != last {
                print("\(timestamp())  \(description)")
                last = description
            }
            usleep(200_000)
        }
    }

    private static let header =
        "time         state  holder (⚠︎ = frontmost app, not necessarily the enabler)"

    /// The state half of an output line — everything after the timestamp. Used
    /// both to render and (compared verbatim) to suppress unchanged repeats.
    /// Reads the same `SecureInput.current()` snapshot the release app uses.
    private static func stateDescription() -> String {
        let snapshot = SecureInput.current()
        guard snapshot.enabled else {
            log.debug("secure input off")
            return "off"
        }
        if snapshot.screenLocked {
            return "ON     SCREEN LOCKED — attribution masked as loginwindow"
        }
        guard let pid = snapshot.holderPID, pid > 0 else {
            return "ON     holder unknown (no kCGSSessionSecureInputPID)"
        }

        let name = snapshot.holderName ?? "pid \(pid)"
        let bundle = snapshot.holderBundleID ?? "?"
        let tag = snapshot.holderIsFrontmost
            ? "⚠︎ ==frontmost — likely NOT the real holder"
            : "background — distinct from frontmost, worth investigating"

        log.debug("secure input on; reported pid \(pid) (\(name, privacy: .public))")
        return "ON     \(name) [\(bundle)] pid \(pid)  — \(tag)"
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    /// Render the Secure Keyboard Entry window to light/dark PNGs (seeded with
    /// representative state), reusing `SnapshotRunner`'s offscreen capture.
    private static func renderShots(into dir: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let outURL = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

        let monitor = SecureInputMonitor()
        monitor.debugSeed()
        let size = NSSize(width: 480, height: 540)
        for (suffix, name) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            let appearance = NSAppearance(named: name)
            NSApp.appearance = appearance
            // An opaque, standard-background window (unlike the panel's clear one)
            // so captured text renders as it does in the real titled window.
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.appearance = appearance
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            let root = SecureInputDiagnosticsView(monitor: monitor)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
            let hosting = NSHostingView(rootView: root)
            hosting.appearance = appearance
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.autoresizingMask = [.width, .height]
            window.contentView = hosting
            window.orderFront(nil)
            SnapshotRunner.settle(0.5)
            let url = outURL.appendingPathComponent("secinput-\(suffix).png")
            if SnapshotRunner.capture(window, to: url) { print(url.path) }
            window.orderOut(nil)
        }
        exit(0)
    }

    /// Render the block banner over a mock window region, both message variants,
    /// so the two-line wrap can be eyeballed without triggering secure input live.
    private static func renderBanners(into dir: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let outURL = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
        let size = NSSize(width: 900, height: 260)
        let messages = [
            ("named", """
                Karabiner-EventViewer is holding Secure Keyboard Entry — keys can't reach Key Monster.
                Quit it (or any keystroke viewer) to release it.
                """),
            ("generic", """
                Secure Keyboard Entry is on — keys can't reach Key Monster.
                Quit any keystroke viewer, like Karabiner-Elements' Event Viewer, to release it.
                """)
        ]
        for (name, text) in messages {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            let view = HintOverlayView(frame: NSRect(origin: .zero, size: size))
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(calibratedWhite: 0.25, alpha: 1).cgColor
            view.windowRegion = view.bounds
            view.banner = text
            window.contentView = view
            window.orderFront(nil)
            SnapshotRunner.settle(0.3)
            let url = outURL.appendingPathComponent("banner-\(name).png")
            if SnapshotRunner.capture(window, to: url) { print(url.path) }
            window.orderOut(nil)
        }
        exit(0)
    }
}
#endif
