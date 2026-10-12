import AppKit
import Foundation

/// Whether kitty link hints can work, step by step, with a fix for whatever
/// doesn't. The same report drives the Settings status and the message shown
/// when hint mode finds nothing in kitty, so what you read in either place is
/// the same diagnosis.
struct KittyHealth: Equatable {
    enum Level: Equatable {
        case healthy
        /// Works, but something will quietly not be hinted.
        case warning
        /// Link hints can't work at all until this is fixed.
        case problem
    }

    struct Item: Equatable {
        let title: String
        let level: Level
        let detail: String
    }

    let items: [Item]

    /// The first thing that isn't fine, which is what to tell the user.
    var firstIssue: Item? { items.first { $0.level != .healthy } }

    /// What the checks need from the outside world, so the logic is testable.
    struct Environment {
        /// Nil when kitty isn't running.
        var kittyPID: pid_t?
        var socketPath: String?
        var kittenExists: Bool
        /// Talks to kitty over its socket; nil when there's no socket to use.
        var run: KittyRemote.Runner?
        /// `tmux show -g terminal-features`; nil when tmux isn't running.
        var tmuxTerminalFeatures: String?
    }

    static func check(_ environment: Environment) -> KittyHealth {
        guard environment.kittyPID != nil else {
            return KittyHealth(items: [Item(title: "Kitty", level: .healthy, detail: "Not running")])
        }
        guard environment.socketPath != nil, let run = environment.run else {
            return KittyHealth(items: [Item(
                title: "Remote control socket", level: .problem,
                detail: "Kitty isn't listening on a socket. Add `listen_on unix:/tmp/kitty` to "
                    + "kitty.conf and restart kitty."
            )])
        }
        guard environment.kittenExists else {
            return KittyHealth(items: [Item(
                title: "kitten", level: .problem,
                detail: "Couldn't find the kitten tool inside the kitty app."
            )])
        }
        guard let listing = run(["ls"]) else {
            return KittyHealth(items: [Item(
                title: "Remote control", level: .problem,
                detail: "Kitty refused the connection. Add `allow_remote_control yes` "
                    + "(or `socket-only`) to kitty.conf and restart kitty."
            )])
        }

        var items = [Item(title: "Remote control", level: .healthy, detail: "Connected to kitty")]
        if KittyRemote.activeTabWindowCounts(inLS: listing).contains(where: { $0 > 1 }) {
            items.append(Item(
                title: "Splits", level: .warning,
                detail: "A kitty tab has split windows; hints work in single-window tabs only."
            ))
        }
        if let features = environment.tmuxTerminalFeatures,
           !tmuxForwardsHyperlinks(terminalFeatures: features) {
            items.append(Item(
                title: "tmux hyperlinks", level: .warning,
                detail: "tmux strips link targets before kitty sees them, so linked text won't "
                    + "be hinted (plain URLs still are). Add "
                    + "`set -ga terminal-features \",xterm-kitty:hyperlinks\"` to tmux.conf."
            ))
        }
        return KittyHealth(items: items)
    }

    /// Whether tmux's `terminal-features` (as `show -g` prints them, one
    /// `terminal-features[N] pattern:feature:…` per line) give `xterm-kitty` the
    /// `hyperlinks` feature. The pattern is a glob matched against `$TERM`.
    static func tmuxForwardsHyperlinks(terminalFeatures: String, term: String = "xterm-kitty") -> Bool {
        terminalFeatures.split(whereSeparator: \.isNewline).contains { line in
            guard let value = line.split(separator: " ", maxSplits: 1).last else { return false }
            let fields = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")).split(separator: ":")
            guard let pattern = fields.first, fields.dropFirst().contains("hyperlinks") else { return false }
            return fnmatch(String(pattern), term, 0) == 0
        }
    }
}

extension KittyHealth {
    /// The real environment. Spawns a few short processes, so call it off the
    /// main thread when a UI is waiting. Looks at the frontmost kitty, or any
    /// running one (Settings is frontmost while it's displayed).
    static func live() -> KittyHealth {
        let kitty = NSWorkspace.shared.frontmostApplication.flatMap {
            $0.bundleIdentifier == KittyRemote.bundleID ? $0 : nil
        } ?? NSRunningApplication.runningApplications(withBundleIdentifier: KittyRemote.bundleID).first

        let kitten = kitty?.bundleURL?.appendingPathComponent("Contents/MacOS/kitten")
        return check(Environment(
            kittyPID: kitty?.processIdentifier,
            socketPath: kitty.flatMap { KittySocket.discover(pid: $0.processIdentifier) },
            kittenExists: kitten.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false,
            run: kitty.flatMap { KittyRemote.runner(for: $0, logMissingSocket: false) },
            tmuxTerminalFeatures: tmuxTerminalFeatures()
        ))
    }

    private static func tmuxTerminalFeatures() -> String? {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              let output = KittyRemote.execute(
                URL(fileURLWithPath: path), ["show", "-g", "terminal-features"], timeout: 1
              ) else { return nil } // tmux isn't installed, or no server is running
        return String(bytes: output, encoding: .utf8)
    }
}
