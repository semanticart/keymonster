import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "bookmarks.editor")

/// "Edit Bookmarks": opens the bookmarks CSV file (see `BookmarksStore`)
/// directly in the user's configured editor — the same `$EDITOR`/terminal
/// settings as "Edit in Editor" (`AppSettings.editorCommand`/`.editorTerminal`/
/// `.quitEditorTerminal`) — and waits for it to exit. Bookmarks are edited by
/// hand in the file rather than through in-app rows.
///
/// Structurally parallel to `ExternalEditorController` but considerably
/// simpler: there's no field to capture, no round-trip newline handling, and
/// no write-back — the editor is pointed straight at the real bookmarks file,
/// so saving in the editor *is* the write. Deliberately not built on top of
/// `ExternalEditorController` (see its `Dependencies`, mostly AX-specific and
/// inapplicable here) — the reusable parts of "Edit in Editor" are the pure
/// pieces in `ExternalEditor.swift` and `TerminalOpener.swift`, called as-is
/// below; the orchestration around them is small enough to duplicate rather
/// than force a shared base onto two very different callers.
@MainActor
final class BookmarksEditorController {
    /// The name failures are logged under (see `ScriptLog`) and Settings
    /// matches on to surface them beside this feature's own controls.
    static let logName = "Edit Bookmarks"

    /// Shared, unlike `ExternalEditorController`: both the global hotkey and
    /// the "Edit Bookmarks…" button in Settings need to drive the same edit.
    static let shared = BookmarksEditorController()

    /// One edit, from trigger to exit. Only what the launch/poll machinery
    /// needs — no captured field, no original text.
    private final class Session {
        let id = UUID()
        let directory: URL
        var poll: Timer?
        /// The terminal instance started for this edit, if a new one was; the
        /// app's to quit once the editor is done.
        var terminal: TerminalInstance?

        init(directory: URL) {
            self.directory = directory
        }

        var statusFile: URL { directory.appendingPathComponent("status") }
        var scriptFile: URL { directory.appendingPathComponent(EditorWrapperScript.fileName) }
    }

    private let dependencies: Dependencies
    private var session: Session?

    /// How the user hears about a failure; injectable for tests.
    var reportFailure: (String) -> Void = { detail in
        ScriptLog.shared.record(script: BookmarksEditorController.logName, detail: detail)
        NSSound.beep()
    }

    /// Called after the editor exits cleanly, so a listener (the Settings tab)
    /// can refresh what it shows.
    var onFinish: () -> Void = {}

    init(dependencies: Dependencies = Dependencies()) {
        self.dependencies = dependencies
    }

    /// How often the status file is checked while a terminal hosts the editor.
    private let pollInterval: TimeInterval = 0.25
    /// How long after the editor exits its terminal instance is asked to quit.
    var terminalQuitDelay: TimeInterval = 0.5

    var isActive: Bool { session != nil }

    /// Opens the bookmarks file in the user's editor. Unlike
    /// `ExternalEditorController.trigger()`, a re-trigger while an edit is
    /// already open is a no-op rather than abandon-and-restart: there's only
    /// ever one file, so restarting would capture nothing new.
    func trigger() {
        guard session == nil else {
            log.info("bookmarks edit already in progress")
            return
        }
        start()
    }

    // MARK: - Start

    private func start() {
        do {
            try BookmarksStore.ensureExists(at: dependencies.bookmarksFileURL())
        } catch {
            reportFailure("could not create the bookmarks file: \(error.localizedDescription)")
            return
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keymonster-bookmarks-edit-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            reportFailure("could not create a working directory: \(error.localizedDescription)")
            return
        }
        let session = Session(directory: directory)
        self.session = session
        log.info("bookmarks edit \(session.id) started")

        launch(session, configuredEditor: dependencies.editorCommand(), terminal: dependencies.editorTerminal())
    }

    // MARK: - Launch

    /// Resolving the editor means running the login shell, so that and the
    /// launch happen off the main thread; results come back keyed by session id.
    private func launch(_ session: Session, configuredEditor: String, terminal: AppRef?) {
        let id = session.id
        let textPath = dependencies.bookmarksFileURL().path
        let statusPath = session.statusFile.path
        let scriptPath = session.scriptFile.path
        let terminalURL = terminal.flatMap { dependencies.terminalAppURL($0.bundleID) }
        if let terminal, terminalURL == nil {
            finish(id, failure: "terminal app \(terminal.name) is not installed")
            return
        }

        let loadEnvironment = dependencies.loginEnvironment
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let environment = loadEnvironment()
            guard let editor = EditorCommand.resolve(configured: configuredEditor, environment: environment) else {
                Task { @MainActor in
                    self.finish(id, failure: "no editor configured: set one in Settings, "
                        + "or export $\(EditorCommand.environmentVariable), $VISUAL, or $EDITOR in your shell")
                }
                return
            }
            let script = EditorWrapperScript.render(
                editor: editor, textFile: textPath, statusFile: statusPath, path: environment["PATH"]
            )
            do {
                try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptPath)
            } catch {
                Task { @MainActor in
                    self.finish(id, failure: "could not write the editor script: \(error.localizedDescription)")
                }
                return
            }
            log.info("bookmarks edit \(id) running editor: \(editor, privacy: .public)")

            if let terminal, let terminalURL {
                Task { @MainActor in
                    await self.launchInTerminal(id, terminal: terminal, appURL: terminalURL, scriptPath: scriptPath)
                }
            } else {
                self.launchDirectly(id, scriptPath: scriptPath, statusPath: statusPath, environment: environment)
            }
        }
    }

    /// GUI editors: run the wrapper here and wait for it.
    private nonisolated func launchDirectly(
        _ id: UUID, scriptPath: String, statusPath: String, environment: [String: String]
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptPath]
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            Task { @MainActor in
                self.finish(id, failure: "could not run the editor: \(error.localizedDescription)")
            }
            return
        }
        // Drain stderr before waiting so a chatty editor can't block on a full pipe.
        let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        let status = Self.readStatus(at: statusPath) ?? process.terminationStatus
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Task { @MainActor in self.finish(id, status: status, stderr: stderr) }
    }

    /// Terminal editors: ask the terminal app to open a window on the wrapper,
    /// then poll for the status file it writes when the editor exits.
    private func launchInTerminal(_ id: UUID, terminal: AppRef, appURL: URL, scriptPath: String) async {
        let launch = TerminalLaunch.make(bundleID: terminal.bundleID, script: scriptPath)
        let instance: TerminalInstance?
        do {
            instance = try await dependencies.openTerminal(launch, appURL, scriptPath)
        } catch {
            finish(id, failure: "could not open \(terminal.name): \(error.localizedDescription)")
            return
        }
        guard let session, session.id == id else { return }
        if let instance {
            log.info("edit \(id) started \(terminal.name, privacy: .public) instance \(instance.processIdentifier)")
        }
        session.terminal = instance
        pollForStatus(id)
    }

    /// Quits the terminal instance started for this edit, if there was one and
    /// the user wants that. Never touches a terminal the script was handed to
    /// as a document: that one was the user's already.
    private func quitTerminalIfOwned(_ session: Session) {
        guard let terminal = session.terminal, dependencies.quitTerminalWhenDone() else { return }
        let id = session.id
        DispatchQueue.main.asyncAfter(deadline: .now() + terminalQuitDelay) {
            let outcome = terminal.terminate() ? "quit" : "would not quit"
            log.info("edit \(id): terminal instance \(terminal.processIdentifier) \(outcome, privacy: .public)")
        }
    }

    private func pollForStatus(_ id: UUID) {
        guard let session, session.id == id else { return }
        session.poll = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let session = self.session, session.id == id else { return }
                guard let status = Self.readStatus(at: session.statusFile.path) else { return }
                self.finish(id, status: status, stderr: "")
            }
        }
    }

    private nonisolated static func readStatus(at path: String) -> Int32? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Finish

    private func finish(_ id: UUID, failure: String) {
        guard let session = takeSession(id) else { return }
        log.error("bookmarks edit \(id) failed: \(failure, privacy: .public)")
        cleanUp(session)
        reportFailure(failure)
    }

    private func finish(_ id: UUID, status: Int32, stderr: String) {
        guard let session = takeSession(id) else { return }
        quitTerminalIfOwned(session)
        cleanUp(session)
        guard status == 0 else {
            log.info("bookmarks edit \(id): editor exited \(status)")
            reportFailure(stderr.isEmpty ? "editor exited \(status)" : "editor exited \(status): \(stderr)")
            return
        }
        log.info("bookmarks edit \(id): done")
        onFinish()
    }

    /// Ends the wait on a session, returning it only if it is still the live one.
    private func takeSession(_ id: UUID) -> Session? {
        guard let session, session.id == id else {
            log.debug("ignoring result for stale bookmarks edit \(id)")
            return nil
        }
        session.poll?.invalidate()
        self.session = nil
        return session
    }

    private func cleanUp(_ session: Session) {
        try? FileManager.default.removeItem(at: session.directory)
    }
}

// MARK: - Dependencies

extension BookmarksEditorController {
    /// The live edges of an edit — settings, the login shell, opening a
    /// terminal — as closures, so the launch/poll/quit flow can be driven in a
    /// test with no login shell and a fake terminal. Defaults are the real
    /// thing, and deliberately read the *same* `AppSettings` editor settings as
    /// `ExternalEditorController.Dependencies` — bookmarks don't get their own.
    struct Dependencies {
        /// Where the bookmarks file lives; overridden in tests to a scratch
        /// file instead of the real `BookmarksStore.defaultURL()`.
        var bookmarksFileURL: @MainActor () -> URL = { BookmarksStore.defaultURL() }
        var editorCommand: @MainActor () -> String = { AppSettings.shared.editorCommand }
        var editorTerminal: @MainActor () -> AppRef? = { AppSettings.shared.editorTerminal }
        var quitTerminalWhenDone: @MainActor () -> Bool = { AppSettings.shared.quitEditorTerminal }
        var terminalAppURL: @MainActor (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
        /// Opens the terminal on the wrapper script; see `TerminalOpener`.
        var openTerminal: @MainActor (TerminalLaunch, URL, String) async throws -> TerminalInstance? = {
            try await TerminalOpener.open($0, app: $1, script: $2)
        }
        /// Runs off the main thread, since it may block on the login shell.
        var loginEnvironment: @Sendable () -> [String: String] = { LoginShellEnvironment.load() }
    }
}
