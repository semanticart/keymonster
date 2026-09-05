import AppKit
import ApplicationServices
import os.log

private let log = Logger(subsystem: "keymonster", category: "editor")

/// "Edit in Editor": hands the focused text field's contents to the user's
/// editor and puts the result back, the way `git commit` hands a message to
/// `$EDITOR`. The hotkey captures the field and its text, writes the text to a
/// file, and runs the editor on it — directly for GUI editors that wait
/// (`code --wait`), or inside a terminal window for the vim-shaped ones.
/// When the editor exits 0, the file's contents replace the field's text; any
/// other exit (`:cq`, a crash) leaves the field untouched, as git would abort
/// the commit. An unchanged file also leaves the field alone.
///
/// The text is written back with a single AX value write when the field takes
/// one, verified by reading it back; otherwise, if the field still has focus,
/// by select-all and paste. If focus moved on, the edited text is left on the
/// clipboard rather than pasted somewhere unintended. Both the capture and
/// the verification read the field's paragraphs rather than its raw value,
/// because Chromium's raw value loses blank lines (see `ParagraphText`).
///
/// The pure pieces — round-trip newline handling, editor resolution, the
/// wrapper script, per-terminal launch arguments — live in `ExternalEditor.swift`.
@MainActor
final class ExternalEditorController {
    /// The name failures are logged under (see `ScriptLog`) and Settings
    /// matches on to surface them beside the feature's own controls.
    static let logName = "Edit in Editor"

    /// One edit, from hotkey to write-back. Kept whole so a stale completion
    /// (an editor closing after the session was cancelled) can be recognised
    /// by id and dropped.
    private final class Session {
        let id = UUID()
        let directory: URL
        let app: NSRunningApplication?
        let element: AXUIElement
        let original: String
        let addedTrailingNewline: Bool
        var poll: Timer?

        init(directory: URL, app: NSRunningApplication?, element: AXUIElement,
             original: String, addedTrailingNewline: Bool) {
            self.directory = directory
            self.app = app
            self.element = element
            self.original = original
            self.addedTrailingNewline = addedTrailingNewline
        }

        var textFile: URL { directory.appendingPathComponent("text.txt") }
        var statusFile: URL { directory.appendingPathComponent("status") }
        var scriptFile: URL { directory.appendingPathComponent(EditorWrapperScript.fileName) }
    }

    private let dependencies: Dependencies
    private var session: Session?

    /// How the user hears about a failure; injectable for tests.
    var reportFailure: (String) -> Void = { detail in
        ScriptLog.shared.record(script: ExternalEditorController.logName, detail: detail)
        NSSound.beep()
    }

    init(dependencies: Dependencies = Dependencies()) {
        self.dependencies = dependencies
    }

    /// How long the target app gets to come forward before the text is
    /// written back into it.
    private let activationDelay: TimeInterval = 0.15
    /// How often the status file is checked while a terminal hosts the editor.
    private let pollInterval: TimeInterval = 0.25

    var isActive: Bool { session != nil }

    /// Fired by the global hotkey. Pressing it while an edit is still open
    /// abandons that one — its editor stays up, but whatever it writes is
    /// ignored — and starts a fresh edit of whatever is focused now.
    func trigger() {
        if let session {
            log.info("abandoning pending edit \(session.id)")
            session.poll?.invalidate()
            self.session = nil
        }
        start()
    }

    // MARK: - Capture

    private func start() {
        guard dependencies.isTrusted() else { dependencies.requestAccess(); return }
        guard let focus = dependencies.focusedField() else {
            log.info("no focused text field to edit")
            NSSound.beep()
            return
        }

        // The paragraph-aware read, not `focus.value`: Chromium's raw value
        // drops blank lines, and the editor should see the field as it looks.
        let original = dependencies.wholeValue(focus.element) ?? focus.value
        let outbound = EditorRoundTrip.outbound(original)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keymonster-edit-\(UUID().uuidString)")
        let session = Session(
            directory: directory,
            app: dependencies.frontmostApplication(),
            element: focus.element,
            original: original,
            addedTrailingNewline: outbound.addedTrailingNewline
        )
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try outbound.fileContents.write(to: session.textFile, atomically: true, encoding: .utf8)
        } catch {
            reportFailure("could not write the text to a temporary file: \(error.localizedDescription)")
            return
        }
        self.session = session
        let appName = session.app?.localizedName ?? "?"
        log.info("edit \(session.id) captured \(original.count) characters from \(appName, privacy: .public)")

        launch(session, configuredEditor: dependencies.editorCommand(),
               terminal: dependencies.editorTerminal())
    }

    // MARK: - Launch

    /// Resolving the editor means running the login shell, so that and the
    /// launch happen off the main thread; results come back keyed by session id.
    private func launch(_ session: Session, configuredEditor: String, terminal: AppRef?) {
        let id = session.id
        let textPath = session.textFile.path
        let statusPath = session.statusFile.path
        let scriptPath = session.scriptFile.path
        let terminalURL = terminal.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) }
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
            log.info("edit \(id) running editor: \(editor, privacy: .public)")

            if let terminal, let terminalURL {
                self.launchInTerminal(id, terminal: terminal, appURL: terminalURL, scriptPath: scriptPath)
            } else {
                self.launchDirectly(id, scriptPath: scriptPath, statusPath: statusPath, environment: environment)
            }
        }
    }

    /// GUI editors: run the wrapper here and wait for it. The editor inherits
    /// the login environment, so it is found on the user's real `PATH`.
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
    /// then poll for the status file the wrapper writes when the editor exits —
    /// there is no process of ours to wait on.
    private nonisolated func launchInTerminal(_ id: UUID, terminal: AppRef, appURL: URL, scriptPath: String) {
        let launch = TerminalLaunch.make(bundleID: terminal.bundleID, appPath: appURL.path, script: scriptPath)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executablePath)
        process.arguments = launch.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            Task { @MainActor in
                self.finish(id, failure: "could not open \(terminal.name): \(error.localizedDescription)")
            }
            return
        }
        let stderrData = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = stderr.isEmpty ? "exited \(process.terminationStatus)" : stderr
            Task { @MainActor in self.finish(id, failure: "could not open \(terminal.name): \(detail)") }
            return
        }
        Task { @MainActor in self.pollForStatus(id) }
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
        log.error("edit \(id) failed: \(failure, privacy: .public)")
        cleanUp(session)
        reportFailure(failure)
    }

    private func finish(_ id: UUID, status: Int32, stderr: String) {
        guard let session = takeSession(id) else { return }
        guard status == 0 else {
            log.info("edit \(id): editor exited \(status); leaving the field untouched")
            cleanUp(session)
            reportFailure(stderr.isEmpty ? "editor exited \(status)" : "editor exited \(status): \(stderr)")
            return
        }
        guard let contents = try? String(contentsOf: session.textFile, encoding: .utf8) else {
            cleanUp(session)
            reportFailure("could not read the edited text back")
            return
        }
        cleanUp(session)
        let edited = EditorRoundTrip.inbound(contents, addedTrailingNewline: session.addedTrailingNewline)
        guard edited != session.original else {
            log.info("edit \(id): unchanged")
            session.app?.activate()
            return
        }
        writeBack(edited, session: session)
    }

    /// Ends the wait on a session, returning it only if it is still the live one.
    private func takeSession(_ id: UUID) -> Session? {
        guard let session, session.id == id else {
            log.debug("ignoring result for stale edit \(id)")
            return nil
        }
        session.poll?.invalidate()
        self.session = nil
        return session
    }

    private func cleanUp(_ session: Session) {
        try? FileManager.default.removeItem(at: session.directory)
    }

    // MARK: - Write back

    private func writeBack(_ text: String, session: Session) {
        // Bring the app forward first: the AX write works either way, but the
        // paste fallback needs the field frontmost, and the user wants to be
        // back in it regardless.
        session.app?.activate()
        self.session = session
        let id = session.id
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let session = self.session, session.id == id else { return }
                self.session = nil
                self.replace(text, in: session)
            }
        }
    }

    private func replace(_ text: String, in session: Session) {
        if dependencies.setValue(session.element, text) {
            log.info("edit \(session.id): replaced via AX value")
            return
        }
        guard dependencies.isFocused(session.element) else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            reportFailure("the field lost focus before the text could be put back; "
                + "the edited text is on the clipboard")
            return
        }
        log.info("edit \(session.id): field rejected the AX write; pasting instead")
        dependencies.replaceAllByPasting(text)
    }
}

// MARK: - Dependencies

extension ExternalEditorController {
    /// The live edges of an edit — trust, focus, the field's reads and writes,
    /// settings, the login shell — as closures, so the whole capture → editor →
    /// write-back decision can be driven in a test against a fake field with
    /// no accessibility grant and no login shell. Defaults are the real thing.
    struct Dependencies {
        var isTrusted: @MainActor () -> Bool = { Paster.isTrusted }
        var requestAccess: @MainActor () -> Void = { _ = Paster.requestAccess() }
        var focusedField: @MainActor () -> AXFocusedText.Focus? = { AXFocusedText.focused() }
        var wholeValue: @MainActor (AXUIElement) -> String? = { AXFocusedText.wholeValue(of: $0) }
        var setValue: @MainActor (AXUIElement, String) -> Bool = { AXFocusedText.setValue($0, to: $1) }
        var isFocused: @MainActor (AXUIElement) -> Bool = { AXFocusedText.isFocused($0) }
        var replaceAllByPasting: @MainActor (String) -> Void = { Paster.replaceAll(with: $0) }
        var frontmostApplication: @MainActor () -> NSRunningApplication? = {
            NSWorkspace.shared.frontmostApplication
        }
        var editorCommand: @MainActor () -> String = { AppSettings.shared.editorCommand }
        var editorTerminal: @MainActor () -> AppRef? = { AppSettings.shared.editorTerminal }
        /// Runs off the main thread, since it may block on the login shell.
        var loginEnvironment: @Sendable () -> [String: String] = { LoginShellEnvironment.load() }
    }
}
