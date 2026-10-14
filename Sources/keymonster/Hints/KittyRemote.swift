import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints.kitty")

/// Reads the frontmost kitty window's screen text through kitty's remote
/// control, which is how hint mode finds URLs and OSC 8 hyperlinks in a
/// terminal whose accessibility tree is just one opaque text area.
///
/// Needs `listen_on unix:/tmp/kitty` (kitty appends the pid) alongside
/// `allow_remote_control` in kitty.conf: an app outside kitty has no tty to
/// talk over, so it needs the socket.
enum KittyRemote {
    static let bundleID = "net.kovidgoyal.kitty"

    /// What a screen read returns: the text with escapes (`--ansi` keeps OSC 8
    /// hyperlink targets) and the window's size in cells.
    struct Screen: Equatable {
        let ansiText: String
        let columns: Int
        let lines: Int
        /// The window's working directory, to resolve relative paths against.
        var cwd: String?
    }

    struct WindowInfo: Equatable {
        let columns: Int
        let lines: Int
        let cwd: String?
    }

    /// Runs one `kitten @` subcommand against the right kitty and returns its
    /// stdout, or nil if it failed. Injectable so `screen(run:)` is testable.
    typealias Runner = (_ subcommand: [String]) -> Data?

    static func screen(run: Runner) -> Screen? {
        guard let listing = run(["ls"]), let size = focusedWindowInfo(inLS: listing) else {
            return nil
        }
        guard let data = run(["get-text", "--match", "state:focused", "--ansi"]),
              let text = String(bytes: data, encoding: .utf8) else {
            return nil
        }
        return Screen(ansiText: text, columns: size.columns, lines: size.lines, cwd: size.cwd)
    }

    /// The focused window's size in cells, from `kitten @ ls` JSON. Nil when no
    /// window is focused, or when the tab holds several windows (kitty splits):
    /// `ls` reports no pane geometry, so cell positions couldn't be placed.
    static func focusedWindowSize(inLS data: Data) -> (columns: Int, lines: Int)? {
        focusedWindowInfo(inLS: data).map { ($0.columns, $0.lines) }
    }

    /// `focusedWindowSize` plus the window's working directory.
    static func focusedWindowInfo(inLS data: Data) -> WindowInfo? {
        guard let osWindows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return nil
        }
        for osWindow in osWindows where osWindow["is_focused"] as? Bool == true {
            let tabs = (osWindow["tabs"] as? [[String: Any]]) ?? []
            for tab in tabs where tab["is_active"] as? Bool == true {
                let windows = (tab["windows"] as? [[String: Any]]) ?? []
                guard windows.count == 1 else {
                    log.info("kitty tab has \(windows.count) windows; link hints need a single one")
                    return nil
                }
                guard let columns = windows[0]["columns"] as? Int,
                      let lines = windows[0]["lines"] as? Int else { return nil }
                return WindowInfo(columns: columns, lines: lines, cwd: windows[0]["cwd"] as? String)
            }
        }
        return nil
    }

    /// Asks kitty to open `url` the way a click on it would — through its
    /// `open_url_with` and `open-actions.conf`, so e.g. file links still land in
    /// the user's editor overlay. False if kitty couldn't be reached.
    static func openLink(_ url: String, run: Runner) -> Bool {
        run(["action", "open_url", url]) != nil
    }

    /// How many windows each active tab holds, from `kitten @ ls` JSON — more
    /// than one means kitty splits. Unlike `focusedWindowSize`, it doesn't need
    /// kitty to be the focused app, so Settings can ask it too.
    static func activeTabWindowCounts(inLS data: Data) -> [Int] {
        guard let osWindows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return osWindows.flatMap { ($0["tabs"] as? [[String: Any]]) ?? [] }
            .filter { $0["is_active"] as? Bool == true }
            .map { (($0["windows"] as? [[String: Any]]) ?? []).count }
    }

    /// A runner that shells out to the `kitten` inside `app`'s bundle, aimed at
    /// the socket that process is listening on. Nil when there is none (the
    /// log line says how to fix it unless `logMissingSocket` is off, as it is
    /// for the Settings check that expects this to happen).
    static func runner(
        for app: NSRunningApplication, timeout: TimeInterval = 1, logMissingSocket: Bool = true
    ) -> Runner? {
        guard let socket = KittySocket.discover(pid: app.processIdentifier) else {
            if logMissingSocket {
                log.info("kitty isn't listening on a socket; add `listen_on unix:/tmp/kitty` to kitty.conf")
            }
            return nil
        }
        guard let kitten = app.bundleURL?.appendingPathComponent("Contents/MacOS/kitten"),
              FileManager.default.isExecutableFile(atPath: kitten.path) else {
            log.error("no kitten binary in the kitty bundle")
            return nil
        }
        return { subcommand in
            execute(kitten, ["@", "--to", "unix:\(socket)"] + subcommand, timeout: timeout)
        }
    }

    /// Runs a short-lived process and returns its stdout, or nil if it failed to
    /// start, took longer than `timeout`, or exited non-zero.
    static func execute(_ executable: URL, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let stdout = Pipe()
        process.standardOutput = stdout
        do {
            try process.run()
        } catch {
            log.error("\(executable.lastPathComponent, privacy: .public) failed to launch: \(error)")
            return nil
        }
        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0 else {
            let name = executable.lastPathComponent
            log.info("\(name, privacy: .public) exited \(process.terminationStatus)")
            return nil
        }
        return data
    }
}

/// Turns the frontmost kitty window's links into hint targets: reads its screen
/// text, finds URLs and hyperlinks, and places them using the window's text
/// area from the accessibility tree.
@MainActor
enum KittyLinkScanner {
    /// What a scan found, and — when it found nothing — why, if kitty is set up
    /// wrong, so the user hears more than a beep.
    struct Outcome {
        var targets: [HintTarget] = []
        var issue: KittyHealth.Item?
    }

    /// `findFiles` adds the file paths on screen (only worth doing when a
    /// script is set to receive them).
    static func scan(_ app: NSRunningApplication, findFiles: Bool = false) -> Outcome {
        guard app.bundleIdentifier == KittyRemote.bundleID else { return Outcome() }
        guard let run = KittyRemote.runner(for: app),
              let screen = KittyRemote.screen(run: run),
              let frame = textAreaFrame(of: app) else {
            // Couldn't read the window: work out whether that's a setup problem.
            return Outcome(issue: KittyHealth.live().firstIssue)
        }
        let links = TerminalLinks.find(inANSI: screen.ansiText, columns: screen.columns)
        let grid = TerminalGrid(frame: frame, columns: screen.columns, lines: screen.lines)
        var targets = grid.targets(for: links)
        if findFiles { targets += grid.targets(for: files(in: screen)) }
        log.debug("kitty: \(targets.count) targets on a \(screen.columns)x\(screen.lines) grid")
        return Outcome(targets: targets)
    }

    /// Path-like text on `screen` that names a file that exists, one entry per
    /// occurrence.
    private static func files(in screen: KittyRemote.Screen) -> [(file: FileTarget, spans: [CellSpan])] {
        let home = NSHomeDirectory()
        return TerminalLinks.findPaths(inANSI: screen.ansiText, columns: screen.columns).compactMap { candidate in
            guard let path = TerminalPathResolver.resolve(
                candidate.text, cwd: screen.cwd, home: home,
                exists: { FileManager.default.fileExists(atPath: $0) }
            ) else { return nil }
            return (FileTarget(path: path, line: candidate.line, column: candidate.column), candidate.spans)
        }
    }

    /// Hands a picked file to the user's script: path as `$1`, and the line and
    /// column, when the output gave them, in `KEYMONSTER_LINE`/`KEYMONSTER_COLUMN`.
    static func open(_ file: FileTarget, script: String) {
        var environment: [String: String] = [:]
        if let line = file.line { environment["KEYMONSTER_LINE"] = String(line) }
        if let column = file.column { environment["KEYMONSTER_COLUMN"] = String(column) }
        ScriptRunner().run(ScriptShortcut(path: script), arguments: [file.path], environment: environment)
    }

    /// Opens `url` through kitty, falling back to the system's default handler
    /// when kitty's remote control isn't there to ask.
    static func open(_ url: String, in app: NSRunningApplication) {
        if let run = KittyRemote.runner(for: app), KittyRemote.openLink(url, run: run) { return }
        if let target = URL(string: url) { NSWorkspace.shared.open(target) }
    }

    /// Kitty exposes its window content as a single `AXTextArea` the size of the
    /// grid; that frame divided by the cell counts is the cell size.
    private static func textAreaFrame(of app: NSRunningApplication) -> CGRect? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = AXHintTargetFinder.focusedWindow(of: axApp) else { return nil }
        let children = AXHintTargetFinder.attributes(of: window, [kAXChildrenAttribute as String])
        for child in AXHintTargetFinder.children(from: children[0]) {
            let values = AXHintTargetFinder.attributes(of: child, [kAXRoleAttribute as String])
            if values[0] as? String == "AXTextArea" { return AXHintTargetFinder.frame(of: child) }
        }
        return AXHintTargetFinder.frame(of: window)
    }
}
