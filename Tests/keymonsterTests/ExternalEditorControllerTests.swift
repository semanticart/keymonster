import AppKit
import ApplicationServices
import XCTest
@testable import keymonster

/// Drives `ExternalEditorController` end to end — capture, temp file, editor,
/// write-back decision — against a fake field, with `/bin/sh` running a real
/// script as the editor so the wrapper script and its status file are
/// exercised too. The field is shaped like Slack's composer: a raw value that
/// has lost its blank line, a paragraph-aware read that still has it, and an
/// AX value write the field claims to take but doesn't reproduce faithfully.
@MainActor
final class ExternalEditorControllerTests: XCTestCase {
    /// What the controller sees of a field, and what it did to it.
    private final class FakeField {
        let element = AXUIElementCreateSystemWide()
        let rawValue: String
        var wholeValue: String
        let acceptsAXWrite: Bool
        var focused = true
        var axWrites: [String] = []
        var pastes: [String] = []
        var failures: [String] = []
        var clipboard: [String] = []

        init(raw: String, whole: String, acceptsAXWrite: Bool) {
            rawValue = raw
            wholeValue = whole
            self.acceptsAXWrite = acceptsAXWrite
        }
    }

    /// A stand-in terminal app: runs the wrapper the way a real terminal
    /// window would (in the background, nothing of ours to wait on) and
    /// remembers whether the controller quit the instance it "started".
    private final class FakeTerminal: TerminalInstance {
        let processIdentifier: pid_t = 4242
        var launches: [TerminalLaunch] = []
        var terminated = false

        func terminate() -> Bool {
            terminated = true
            return true
        }

        /// Runs the script detached, and returns self as the started instance
        /// for a new-instance launch, nil for a document hand-off.
        func open(_ launch: TerminalLaunch, scriptPath: String) -> TerminalInstance? {
            launches.append(launch)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [scriptPath]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            if case .document = launch { return nil }
            return self
        }
    }

    private let kitty = AppRef(bundleID: "net.kovidgoyal.kitty", name: "kitty")
    private let terminalApp = AppRef(bundleID: "com.apple.Terminal", name: "Terminal")

    private let original = "That’s great to hear.\n\nReally happy for you, buddy."
    private let edited = "That’s great to hear.\n\nReally happy for you, pal."
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keymonster-controller-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: - Tests

    func testSlackShapedFieldKeepsItsBlankLineAndIsPasted() throws {
        let field = FakeField(raw: "That’s great to hear.\nReally happy for you, buddy.",
                              whole: original, acceptsAXWrite: false)
        let controller = makeController(field, editor: try editorScript())
        runEdit(controller)

        // The editor was handed the paragraph-aware text, terminated for vim's sake.
        XCTAssertEqual(try String(contentsOf: capturePath, encoding: .utf8), original + "\n")
        // The AX write was tried first, rejected, and the paste carried the
        // blank line through.
        XCTAssertEqual(field.axWrites, [edited])
        XCTAssertEqual(field.pastes, [edited])
        XCTAssertEqual(field.failures, [])
    }

    func testFieldThatTakesTheAXWriteIsNotPasted() throws {
        let field = FakeField(raw: original, whole: original, acceptsAXWrite: true)
        let controller = makeController(field, editor: try editorScript())
        runEdit(controller)

        XCTAssertEqual(field.axWrites, [edited])
        XCTAssertEqual(field.pastes, [])
        XCTAssertEqual(field.wholeValue, edited)
        XCTAssertEqual(field.failures, [])
    }

    func testUnchangedEditTouchesNothing() {
        let field = FakeField(raw: original, whole: original, acceptsAXWrite: true)
        let controller = makeController(field, editor: "/usr/bin/true")
        runEdit(controller)

        XCTAssertEqual(field.axWrites, [])
        XCTAssertEqual(field.pastes, [])
        XCTAssertEqual(field.failures, [])
    }

    func testFailingEditorLeavesTheFieldAlone() throws {
        // Edits the file and then exits non-zero, like `:cq` after changes.
        let field = FakeField(raw: original, whole: original, acceptsAXWrite: true)
        let controller = makeController(field, editor: try editorScript(exitStatus: 3))
        runEdit(controller)

        XCTAssertEqual(field.axWrites, [])
        XCTAssertEqual(field.pastes, [])
        XCTAssertEqual(field.failures, ["editor exited 3"])
    }

    func testLostFocusLeavesTheTextOnTheClipboardInsteadOfPasting() throws {
        // The user clicked elsewhere while the editor was open: the AX write is
        // refused as before, but a paste would land in the wrong field.
        let field = FakeField(raw: original, whole: original, acceptsAXWrite: false)
        field.focused = false
        let controller = makeController(field, editor: try editorScript())
        runEdit(controller)

        XCTAssertEqual(field.axWrites, [edited])
        XCTAssertEqual(field.pastes, [])
        XCTAssertEqual(field.clipboard, [edited])
        XCTAssertEqual(field.failures.count, 1)
        XCTAssertTrue(field.failures[0].contains("on the clipboard"), field.failures[0])
    }

    func testNoEditorConfiguredReportsHowToSetOne() {
        let field = FakeField(raw: original, whole: original, acceptsAXWrite: true)
        let controller = makeController(field, editor: "")
        runEdit(controller)

        XCTAssertEqual(field.axWrites, [])
        XCTAssertEqual(field.pastes, [])
        XCTAssertEqual(field.failures.count, 1)
        XCTAssertTrue(field.failures[0].hasPrefix("no editor configured"), field.failures[0])
    }

    func testTerminalStartedForTheEditIsQuitOnceTheEditorExits() throws {
        let field = FakeField(raw: original, whole: original, acceptsAXWrite: true)
        let terminal = FakeTerminal()
        let controller = makeController(field, editor: try editorScript(), terminal: kitty, host: terminal)
        runEdit(controller)

        // The edit went through the terminal-hosted path and landed.
        XCTAssertEqual(terminal.launches.count, 1)
        guard case .newInstance(let arguments) = terminal.launches[0] else {
            return XCTFail("kitty should be started as a new instance, got \(terminal.launches[0])")
        }
        XCTAssertEqual(arguments.count, 1)
        XCTAssertTrue(arguments[0].hasSuffix(EditorWrapperScript.fileName), arguments[0])
        XCTAssertEqual(field.axWrites, [edited])
        // ...and the instance that hosted it was quit, a beat later.
        waitUntil("the terminal instance is quit") { terminal.terminated }
    }

    func testTerminalIsLeftRunningWhenTheSettingIsOff() throws {
        let field = FakeField(raw: original, whole: original, acceptsAXWrite: true)
        let terminal = FakeTerminal()
        let controller = makeController(field, editor: try editorScript(), terminal: kitty,
                                        host: terminal, quitTerminal: false)
        runEdit(controller)

        XCTAssertEqual(field.axWrites, [edited])
        RunLoop.main.run(until: Date(timeIntervalSinceNow: controller.terminalQuitDelay * 3))
        XCTAssertFalse(terminal.terminated, "the setting is off, so the instance must be left alone")
    }

    func testTerminalHandedTheScriptAsADocumentIsNeverQuit() throws {
        let field = FakeField(raw: original, whole: original, acceptsAXWrite: true)
        let terminal = FakeTerminal()
        let controller = makeController(field, editor: try editorScript(), terminal: terminalApp, host: terminal)
        runEdit(controller)

        XCTAssertEqual(terminal.launches, [.document])
        XCTAssertEqual(field.axWrites, [edited])
        RunLoop.main.run(until: Date(timeIntervalSinceNow: controller.terminalQuitDelay * 3))
        XCTAssertFalse(terminal.terminated, "Terminal.app was the user's already; nothing of ours to quit")
    }

    // MARK: - Harness

    private var capturePath: URL { directory.appendingPathComponent("editor-saw.txt") }

    /// A stand-in editor: keeps a copy of what it was handed, changes one
    /// word, and exits with `exitStatus`.
    private func editorScript(exitStatus: Int32 = 0) throws -> String {
        let script = directory.appendingPathComponent("editor.sh")
        try """
        #!/bin/sh
        /bin/cp "$1" \(ShellQuote.single(capturePath.path))
        /usr/bin/sed -i '' 's/buddy/pal/' "$1"
        exit \(exitStatus)

        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script.path
    }

    private func makeController(
        _ field: FakeField, editor: String,
        terminal: AppRef? = nil, host: FakeTerminal? = nil, quitTerminal: Bool = true
    ) -> ExternalEditorController {
        var dependencies = ExternalEditorController.Dependencies()
        dependencies.isTrusted = { true }
        dependencies.requestAccess = { XCTFail("should not ask for access when trusted") }
        dependencies.focusedField = { AXFocusedText.Focus(element: field.element, value: field.rawValue) }
        dependencies.wholeValue = { _ in field.wholeValue }
        dependencies.setValue = { _, text in
            field.axWrites.append(text)
            guard field.acceptsAXWrite else { return false }
            field.wholeValue = text
            return true
        }
        dependencies.isFocused = { _ in field.focused }
        dependencies.replaceAllByPasting = { field.pastes.append($0) }
        dependencies.leaveOnClipboard = { field.clipboard.append($0) }
        dependencies.frontmostApplication = { nil }
        dependencies.editorCommand = { editor }
        dependencies.editorTerminal = { terminal }
        dependencies.quitTerminalWhenDone = { quitTerminal }
        dependencies.terminalAppURL = { URL(fileURLWithPath: "/Applications/\($0).app") }
        dependencies.openTerminal = { launch, _, scriptPath in
            guard let host else { throw NSError(domain: "test", code: 1) }
            return host.open(launch, scriptPath: scriptPath)
        }
        let home = directory.path
        dependencies.loginEnvironment = { ["PATH": "/usr/bin:/bin", "HOME": home] }
        let controller = ExternalEditorController(dependencies: dependencies)
        controller.reportFailure = { field.failures.append($0) }
        controller.terminalQuitDelay = 0.05
        return controller
    }

    /// Fires the hotkey and pumps the main run loop until the edit is over:
    /// the editor finishes on a background thread and reports back to the
    /// main actor, and the write-back waits a beat for the app to come forward.
    private func runEdit(_ controller: ExternalEditorController, timeout: TimeInterval = 10) {
        controller.trigger()
        let deadline = Date(timeIntervalSinceNow: timeout)
        while controller.isActive && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertFalse(controller.isActive, "the edit did not finish within \(timeout)s")
    }

    /// Pumps the main run loop until `condition` holds or the timeout passes.
    private func waitUntil(_ what: String, timeout: TimeInterval = 5, _ condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertTrue(condition(), "timed out waiting for \(what)")
    }
}
