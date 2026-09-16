import AppKit
import XCTest
@testable import keymonster

/// Drives `BookmarksEditorController` end to end — the bookmarks file, the
/// editor, the finish decision — with `/bin/sh` running a real script as the
/// editor so the wrapper script and its status file are exercised too.
/// Structurally parallel to `ExternalEditorControllerTests`.
@MainActor
final class BookmarksEditorControllerTests: XCTestCase {
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

    private var directory: URL!
    private var bookmarksURL: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("keymonster-bookmarks-editor-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        bookmarksURL = directory.appendingPathComponent("bookmarks.csv")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    // MARK: - Tests

    func testCleanExitCallsOnFinish() throws {
        var finished = false
        var failures: [String] = []
        let controller = makeController(editor: try editorScript())
        controller.onFinish = { finished = true }
        controller.reportFailure = { failures.append($0) }

        runEdit(controller)

        XCTAssertTrue(finished)
        XCTAssertEqual(failures, [])
    }

    func testCreatesTheBookmarksFileWhenMissing() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: bookmarksURL.path))
        let controller = makeController(editor: try editorScript())

        runEdit(controller)

        XCTAssertTrue(FileManager.default.fileExists(atPath: bookmarksURL.path))
    }

    func testNonZeroExitReportsTheStatus() throws {
        var finished = false
        var failures: [String] = []
        let controller = makeController(editor: try editorScript(exitStatus: 3))
        controller.onFinish = { finished = true }
        controller.reportFailure = { failures.append($0) }

        runEdit(controller)

        XCTAssertFalse(finished)
        XCTAssertEqual(failures, ["editor exited 3"])
    }

    func testNoEditorConfiguredReportsHowToSetOne() {
        var failures: [String] = []
        let controller = makeController(editor: "")
        controller.reportFailure = { failures.append($0) }

        runEdit(controller)

        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures[0].hasPrefix("no editor configured"), failures[0])
    }

    func testUninstalledTerminalReportsNotInstalled() throws {
        var failures: [String] = []
        let controller = makeController(
            editor: try editorScript(), terminal: kitty, host: nil, terminalInstalled: false
        )
        controller.reportFailure = { failures.append($0) }

        runEdit(controller)

        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures[0].contains("is not installed"), failures[0])
    }

    func testTerminalStartedForTheEditIsQuitOnceTheEditorExits() throws {
        var finished = false
        let terminal = FakeTerminal()
        let controller = makeController(editor: try editorScript(), terminal: kitty, host: terminal)
        controller.onFinish = { finished = true }

        runEdit(controller)

        XCTAssertEqual(terminal.launches.count, 1)
        guard case .newInstance(let arguments) = terminal.launches[0] else {
            return XCTFail("kitty should be started as a new instance, got \(terminal.launches[0])")
        }
        XCTAssertEqual(arguments.count, 1)
        XCTAssertTrue(arguments[0].hasSuffix(EditorWrapperScript.fileName), arguments[0])
        XCTAssertTrue(finished)
        waitUntil("the terminal instance is quit") { terminal.terminated }
    }

    func testTerminalIsLeftRunningWhenTheSettingIsOff() throws {
        let terminal = FakeTerminal()
        let controller = makeController(
            editor: try editorScript(), terminal: kitty, host: terminal, quitTerminal: false
        )

        runEdit(controller)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: controller.terminalQuitDelay * 3))
        XCTAssertFalse(terminal.terminated, "the setting is off, so the instance must be left alone")
    }

    func testTerminalHandedTheScriptAsADocumentIsNeverQuit() throws {
        let terminal = FakeTerminal()
        let controller = makeController(editor: try editorScript(), terminal: terminalApp, host: terminal)

        runEdit(controller)

        XCTAssertEqual(terminal.launches, [.document])
        RunLoop.main.run(until: Date(timeIntervalSinceNow: controller.terminalQuitDelay * 3))
        XCTAssertFalse(terminal.terminated, "Terminal.app was the user's already; nothing of ours to quit")
    }

    func testRetriggerWhileActiveIsANoOp() throws {
        let controller = makeController(editor: try editorScript(delay: 0.3))
        controller.trigger()
        XCTAssertTrue(controller.isActive)
        controller.trigger() // should not abandon/restart the in-flight session
        XCTAssertTrue(controller.isActive)

        let deadline = Date(timeIntervalSinceNow: 10)
        while controller.isActive && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertFalse(controller.isActive)
    }

    // MARK: - Harness

    /// A stand-in editor that exits with `exitStatus`, optionally after a
    /// short delay so a re-trigger can be exercised while it's still "open".
    private func editorScript(exitStatus: Int32 = 0, delay: TimeInterval = 0) throws -> String {
        let script = directory.appendingPathComponent("editor.sh")
        try """
        #!/bin/sh
        sleep \(delay)
        exit \(exitStatus)

        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script.path
    }

    private func makeController(
        editor: String, terminal: AppRef? = nil, host: FakeTerminal? = nil,
        quitTerminal: Bool = true, terminalInstalled: Bool = true
    ) -> BookmarksEditorController {
        var dependencies = BookmarksEditorController.Dependencies()
        let url = bookmarksURL!
        dependencies.bookmarksFileURL = { url }
        dependencies.editorCommand = { editor }
        dependencies.editorTerminal = { terminal }
        dependencies.quitTerminalWhenDone = { quitTerminal }
        dependencies.terminalAppURL = { terminalInstalled ? URL(fileURLWithPath: "/Applications/\($0).app") : nil }
        dependencies.openTerminal = { launch, _, scriptPath in
            guard let host else { throw NSError(domain: "test", code: 1) }
            return host.open(launch, scriptPath: scriptPath)
        }
        let home = directory.path
        dependencies.loginEnvironment = { ["PATH": "/usr/bin:/bin", "HOME": home] }
        let controller = BookmarksEditorController(dependencies: dependencies)
        controller.terminalQuitDelay = 0.05
        return controller
    }

    /// Fires the trigger and pumps the main run loop until the edit is over.
    private func runEdit(_ controller: BookmarksEditorController, timeout: TimeInterval = 10) {
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
