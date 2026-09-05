import Foundation
import os.log

private let log = Logger(subsystem: "keymonster", category: "editor")

/// The environment a user's shell would have, read by asking their login shell
/// to print it. A menu bar app launched by Finder or at login inherits none of
/// the user's profile — no Homebrew `PATH`, no `$EDITOR` — and the profile is
/// written in whichever shell they chose (zsh, fish, bash…), so the only
/// shell-agnostic way to learn what it sets is to run it.
enum LoginShellEnvironment {
    /// The user's login shell from the account record, not `$SHELL` — the app's
    /// own environment may not carry it.
    static func userShell() -> String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        return "/bin/zsh"
    }

    /// Blocking: runs the login shell and waits for it, so call it off the main
    /// thread. `env -0` separates entries with NUL rather than newline, so values
    /// containing newlines survive; chatter a profile prints to stdout is dropped
    /// by the parser because it doesn't look like `NAME=value`. If the shell
    /// hangs (a profile waiting on input) it is killed after `timeout` and the
    /// app's own environment is used instead — worse, but never stuck.
    static func load(shell: String = userShell(), timeout: TimeInterval = 5) -> [String: String] {
        let fallback = ProcessInfo.processInfo.environment
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "exec /usr/bin/env -0"]
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let stdout = Pipe()
        process.standardOutput = stdout
        do {
            try process.run()
        } catch {
            log.error("login shell \(shell, privacy: .public) failed to launch: \(error)")
            return fallback
        }

        let watchdog = DispatchWorkItem { [process] in
            if process.isRunning {
                log.error("login shell \(shell, privacy: .public) took over \(timeout)s; killing it")
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        watchdog.cancel()

        let parsed = parse(data)
        guard process.terminationStatus == 0, !parsed.isEmpty else {
            let status = process.terminationStatus
            log.error("login shell \(shell, privacy: .public) exited \(status); using app environment")
            return fallback
        }
        return fallback.merging(parsed) { _, login in login }
    }

    /// Parses `env -0` output: NUL-separated `NAME=value` entries. Anything
    /// without an `=` (profile chatter) is ignored.
    static func parse(_ data: Data) -> [String: String] {
        var result: [String: String] = [:]
        for entry in data.split(separator: 0) {
            guard let text = String(data: entry, encoding: .utf8),
                  let separator = text.firstIndex(of: "=") else { continue }
            let name = String(text[..<separator])
            guard !name.isEmpty else { continue }
            result[name] = String(text[text.index(after: separator)...])
        }
        return result
    }
}
