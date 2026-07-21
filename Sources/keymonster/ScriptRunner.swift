import Foundation
import os.log

private let log = Logger(subsystem: "keymonster", category: "scripts")

/// Binds a global shortcut to a script file on disk. Only the path is stored;
/// how it runs is inferred from the file (see `ScriptInvocation`).
struct ScriptShortcut: Codable, Equatable, Identifiable {
    var id: UUID
    var shortcut: Shortcut?
    var path: String

    init(id: UUID = UUID(), shortcut: Shortcut? = nil, path: String = "") {
        self.id = id
        self.shortcut = shortcut
        self.path = path
    }

    /// True when no script file has been chosen; such entries register no hotkey.
    var isEmpty: Bool {
        path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The script's file name, for display and logs.
    var displayName: String {
        isEmpty ? "(no script)" : (path as NSString).lastPathComponent
    }
}

/// The exact process a script file maps to, derived purely from its path and
/// executable bit so tests can verify it without spawning anything.
struct ScriptInvocation: Equatable, Sendable {
    let executablePath: String
    let arguments: [String]

    private static let appleScriptExtensions: Set<String> = ["scpt", "scptd", "applescript"]

    /// AppleScript sources and bundles run via osascript. Anything with the
    /// executable bit runs directly, so its shebang picks the interpreter
    /// (bash, python, whatever). Everything else is treated as a shell script
    /// and handed to zsh as a login shell, so the user's profile PATH applies
    /// just as it would pasted into a terminal.
    static func make(path: String, isExecutable: Bool) -> ScriptInvocation {
        let ext = (path as NSString).pathExtension.lowercased()
        if appleScriptExtensions.contains(ext) {
            return ScriptInvocation(executablePath: "/usr/bin/osascript", arguments: [path])
        }
        if isExecutable {
            return ScriptInvocation(executablePath: path, arguments: [])
        }
        return ScriptInvocation(executablePath: "/bin/zsh", arguments: ["-l", path])
    }
}

/// Launches a script shortcut's process in the background; failures go to the
/// unified log and to `ScriptLog` so Settings can surface them.
struct ScriptRunner {
    /// Where failures are reported; injectable for tests.
    var reportFailure: @Sendable (_ script: String, _ detail: String) -> Void = { script, detail in
        DispatchQueue.main.async { ScriptLog.shared.record(script: script, detail: detail) }
    }

    /// Runs the script detached from the caller. `completion` (used by tests)
    /// fires on a background queue with the exit status, or nil if the process
    /// never launched (including entries with no script chosen).
    func run(_ script: ScriptShortcut, completion: (@Sendable (Int32?) -> Void)? = nil) {
        guard !script.isEmpty else {
            completion?(nil)
            return
        }
        let path = (script.path as NSString).expandingTildeInPath
        let name = script.displayName
        let report = reportFailure

        // Everything Process-related happens on one background block: run,
        // stderr drain, wait. Draining stderr before waitUntilExit keeps a
        // chatty script from blocking on a full pipe.
        DispatchQueue.global(qos: .userInitiated).async {
            let invocation = ScriptInvocation.make(
                path: path,
                isExecutable: FileManager.default.isExecutableFile(atPath: path)
            )
            let process = Process()
            process.executableURL = URL(fileURLWithPath: invocation.executablePath)
            process.arguments = invocation.arguments
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            process.standardOutput = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                log.error("script \(name, privacy: .public) failed to launch: \(error)")
                report(name, "failed to launch: \(error.localizedDescription)")
                completion?(nil)
                return
            }
            log.debug("script \(name, privacy: .public) launched")

            let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            process.waitUntilExit()

            let status = process.terminationStatus
            if status != 0 {
                let stderr = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let detail = stderr.isEmpty ? "exited \(status)" : "exited \(status): \(stderr)"
                log.error("script \(name, privacy: .public) \(detail, privacy: .public)")
                report(name, detail)
            }
            completion?(status)
        }
    }
}
