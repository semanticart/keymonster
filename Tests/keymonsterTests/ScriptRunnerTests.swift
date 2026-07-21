import XCTest
@testable import keymonster

final class ScriptInvocationTests: XCTestCase {
    func testAppleScriptFilesRunViaOsascript() {
        for path in ["/tmp/a.scpt", "/tmp/a.scptd", "/tmp/a.applescript", "/tmp/a.AppleScript"] {
            let invocation = ScriptInvocation.make(path: path, isExecutable: true)
            XCTAssertEqual(invocation.executablePath, "/usr/bin/osascript", path)
            XCTAssertEqual(invocation.arguments, [path], path)
        }
    }

    func testExecutableFilesRunDirectly() {
        let invocation = ScriptInvocation.make(path: "/tmp/tool", isExecutable: true)

        XCTAssertEqual(invocation.executablePath, "/tmp/tool")
        XCTAssertEqual(invocation.arguments, [])
    }

    func testNonExecutableFilesRunViaLoginShell() {
        let invocation = ScriptInvocation.make(path: "/tmp/thing.sh", isExecutable: false)

        XCTAssertEqual(invocation.executablePath, "/bin/zsh")
        XCTAssertEqual(invocation.arguments, ["-l", "/tmp/thing.sh"])
    }
}

final class ScriptRunnerTests: XCTestCase {
    private var scriptDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scriptDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keymonster-script-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scriptDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: scriptDir)
        scriptDir = nil
        try super.tearDownWithError()
    }

    private func writeScript(_ name: String, _ contents: String, executable: Bool = false) throws -> String {
        let url = scriptDir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return url.path
    }

    private func runAndWait(_ runner: ScriptRunner, _ script: ScriptShortcut) -> Int32? {
        let done = expectation(description: "script finished")
        let status = Box<Int32?>(nil)
        runner.run(script) { code in
            status.value = code
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        return status.value
    }

    func testNonExecutableScriptRunsInShellAndReportsExitStatus() throws {
        let path = try writeScript("plain.sh", "exit 3")

        XCTAssertEqual(runAndWait(ScriptRunner(), ScriptShortcut(path: path)), 3)
    }

    func testExecutableScriptRunsViaItsShebang() throws {
        let marker = scriptDir.appendingPathComponent("marker")
        let path = try writeScript("tool", "#!/bin/sh\ntouch '\(marker.path)'\n", executable: true)

        XCTAssertEqual(runAndWait(ScriptRunner(), ScriptShortcut(path: path)), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }

    func testTildeInPathIsExpanded() throws {
        // zsh reports a missing file as status 127; reaching that (rather than a
        // launch failure) proves the tilde path was expanded and handed to zsh.
        let status = runAndWait(ScriptRunner(), ScriptShortcut(path: "~/keymonster-no-such-script"))

        XCTAssertEqual(status, 127)
    }

    func testFailureIsReportedWithStderr() throws {
        let path = try writeScript("broken.sh", "echo boom >&2\nexit 9")
        let reported = Box<(String, String)?>(nil)
        var runner = ScriptRunner()
        runner.reportFailure = { script, detail in
            reported.value = (script, detail)
        }

        XCTAssertEqual(runAndWait(runner, ScriptShortcut(path: path)), 9)
        XCTAssertEqual(reported.value?.0, "broken.sh")
        XCTAssertEqual(reported.value?.1, "exited 9: boom")
    }

    func testSuccessReportsNoFailure() throws {
        let path = try writeScript("fine.sh", "exit 0")
        let reported = Box<Bool>(false)
        var runner = ScriptRunner()
        runner.reportFailure = { _, _ in reported.value = true }

        XCTAssertEqual(runAndWait(runner, ScriptShortcut(path: path)), 0)
        XCTAssertFalse(reported.value)
    }

    func testEmptyPathNeverLaunches() {
        XCTAssertNil(runAndWait(ScriptRunner(), ScriptShortcut(path: "   \n")))
    }
}

/// Reference box so @Sendable completions can hand values back to the test.
private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
