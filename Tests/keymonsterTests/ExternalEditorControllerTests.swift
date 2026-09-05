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

    private func makeController(_ field: FakeField, editor: String) -> ExternalEditorController {
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
        dependencies.editorTerminal = { nil }
        let home = directory.path
        dependencies.loginEnvironment = { ["PATH": "/usr/bin:/bin", "HOME": home] }
        let controller = ExternalEditorController(dependencies: dependencies)
        controller.reportFailure = { field.failures.append($0) }
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
}
