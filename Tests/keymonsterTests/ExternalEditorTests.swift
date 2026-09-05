import XCTest
@testable import keymonster

final class EditorRoundTripTests: XCTestCase {
    func testAddsTrailingNewlineWhenMissingAndRemovesItOnTheWayBack() {
        let out = EditorRoundTrip.outbound("hello")
        XCTAssertEqual(out.fileContents, "hello\n")
        XCTAssertTrue(out.addedTrailingNewline)
        XCTAssertEqual(EditorRoundTrip.inbound("hello\n", addedTrailingNewline: true), "hello")
    }

    func testLeavesExistingTrailingNewlineAlone() {
        let out = EditorRoundTrip.outbound("hello\n")
        XCTAssertEqual(out.fileContents, "hello\n")
        XCTAssertFalse(out.addedTrailingNewline)
        XCTAssertEqual(EditorRoundTrip.inbound("hello\n", addedTrailingNewline: false), "hello\n")
    }

    /// Blank lines — between paragraphs and at the very end — survive the round
    /// trip untouched; only the one newline we added is taken back.
    func testPreservesBlankLinesEverywhere() {
        let text = "para one\n\n\npara two\n\n"
        let out = EditorRoundTrip.outbound(text)
        XCTAssertEqual(out.fileContents, text)
        XCTAssertEqual(EditorRoundTrip.inbound(out.fileContents, addedTrailingNewline: out.addedTrailingNewline), text)

        let unterminated = "para one\n\n\npara two"
        let out2 = EditorRoundTrip.outbound(unterminated)
        XCTAssertEqual(out2.fileContents, unterminated + "\n")
        XCTAssertEqual(
            EditorRoundTrip.inbound(out2.fileContents, addedTrailingNewline: out2.addedTrailingNewline),
            unterminated
        )
    }

    /// A user who adds blank lines at the end in the editor keeps them: only one
    /// newline is stripped, never a run.
    func testOnlyOneAddedNewlineIsStripped() {
        XCTAssertEqual(EditorRoundTrip.inbound("hello\n\n\n", addedTrailingNewline: true), "hello\n\n")
    }

    func testEditorRemovingTheNewlineIsFine() {
        XCTAssertEqual(EditorRoundTrip.inbound("hello", addedTrailingNewline: true), "hello")
    }

    func testEmptyTextStaysEmpty() {
        let out = EditorRoundTrip.outbound("")
        XCTAssertEqual(out.fileContents, "")
        XCTAssertFalse(out.addedTrailingNewline)
        XCTAssertEqual(EditorRoundTrip.inbound("", addedTrailingNewline: false), "")
    }
}

final class EditorCommandTests: XCTestCase {
    private let fullEnvironment = [
        "KEY_MONSTER_EDITOR": "nvim -c 'set ft=markdown'",
        "VISUAL": "code --wait",
        "EDITOR": "vi"
    ]

    func testConfiguredSettingWinsOverEverything() {
        XCTAssertEqual(EditorCommand.resolve(configured: "zed --wait", environment: fullEnvironment), "zed --wait")
    }

    func testAppSpecificVariableBeatsVisualAndEditor() {
        XCTAssertEqual(
            EditorCommand.resolve(configured: "", environment: fullEnvironment),
            "nvim -c 'set ft=markdown'"
        )
    }

    func testVisualBeatsEditor() {
        XCTAssertEqual(
            EditorCommand.resolve(configured: "", environment: ["VISUAL": "code --wait", "EDITOR": "vi"]),
            "code --wait"
        )
    }

    func testEditorIsTheLastResort() {
        XCTAssertEqual(EditorCommand.resolve(configured: "", environment: ["EDITOR": "vi"]), "vi")
    }

    func testBlankValuesAreSkipped() {
        XCTAssertEqual(
            EditorCommand.resolve(configured: "  \n", environment: ["VISUAL": "  ", "EDITOR": " nano "]),
            "nano"
        )
    }

    func testNothingConfiguredIsNil() {
        XCTAssertNil(EditorCommand.resolve(configured: "", environment: [:]))
    }
}

final class ShellQuoteTests: XCTestCase {
    func testWrapsInSingleQuotes() {
        XCTAssertEqual(ShellQuote.single("/tmp/a b"), "'/tmp/a b'")
    }

    func testEscapesEmbeddedSingleQuotes() {
        XCTAssertEqual(ShellQuote.single("it's"), "'it'\\''s'")
    }
}

final class TerminalLaunchTests: XCTestCase {
    private let script = "/tmp/x/edit.command"

    func testKnownTerminalsGetANewWindowRunningTheScript() {
        let cases: [(String, [String])] = [
            ("net.kovidgoyal.kitty", ["-na", "/Applications/kitty.app", "--args", script]),
            ("org.alacritty", ["-na", "/Applications/kitty.app", "--args", "-e", script]),
            ("com.github.wez.wezterm", ["-na", "/Applications/kitty.app", "--args", "start", "--", script]),
            ("com.mitchellh.ghostty", ["-na", "/Applications/kitty.app", "--args", "-e", script])
        ]
        for (bundleID, expected) in cases {
            let launch = TerminalLaunch.make(bundleID: bundleID, appPath: "/Applications/kitty.app", script: script)
            XCTAssertEqual(launch.executablePath, "/usr/bin/open", bundleID)
            XCTAssertEqual(launch.arguments, expected, bundleID)
        }
    }

    func testTerminalAppAndUnknownsAreHandedTheCommandFile() {
        for bundleID in ["com.apple.Terminal", "com.googlecode.iterm2", "com.example.someterm"] {
            let launch = TerminalLaunch.make(bundleID: bundleID, appPath: "/Applications/T.app", script: script)
            XCTAssertEqual(launch.arguments, ["-a", "/Applications/T.app", script], bundleID)
        }
    }
}

final class LoginShellEnvironmentTests: XCTestCase {
    func testParsesNulSeparatedEntriesAndSkipsChatter() {
        let raw = "Welcome!\0PATH=/opt/homebrew/bin:/usr/bin\0EDITOR=nvim\0MULTI=a\nb\0=nope\0"
        let env = LoginShellEnvironment.parse(Data(raw.utf8))
        XCTAssertEqual(env, ["PATH": "/opt/homebrew/bin:/usr/bin", "EDITOR": "nvim", "MULTI": "a\nb"])
    }

    func testLoadsFromARealShell() {
        let env = LoginShellEnvironment.load(shell: "/bin/sh")
        XCTAssertFalse(env["PATH", default: ""].isEmpty)
        XCTAssertNotNil(env["HOME"])
    }

    func testUserShellIsAnAbsolutePath() {
        XCTAssertTrue(LoginShellEnvironment.userShell().hasPrefix("/"))
    }
}

/// Runs the rendered wrapper for real under /bin/sh with a stand-in editor, so
/// the quoting, the status hand-off, and the round trip are checked end to end
/// without any terminal or GUI involved.
final class EditorWrapperScriptTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keymonster editor tests \(UUID().uuidString)") // space on purpose
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
        dir = nil
        try super.tearDownWithError()
    }

    private func writeExecutable(_ name: String, _ contents: String) throws -> String {
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func runWrapper(
        editor: String, text: String, path: String? = nil
    ) throws -> (status: String?, text: String) {
        let textFile = dir.appendingPathComponent("it's text.txt").path
        let statusFile = dir.appendingPathComponent("status").path
        try text.write(toFile: textFile, atomically: true, encoding: .utf8)
        let script = EditorWrapperScript.render(editor: editor, textFile: textFile, statusFile: statusFile, path: path)
        let scriptPath = try writeExecutable(EditorWrapperScript.fileName, script)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: scriptPath)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        let status = try? String(contentsOfFile: statusFile, encoding: .utf8)
        let edited = try String(contentsOfFile: textFile, encoding: .utf8)
        return (status?.trimmingCharacters(in: .whitespacesAndNewlines), edited)
    }

    func testRunsTheEditorOnTheFileAndReportsSuccess() throws {
        // An "editor" that appends a line, with a flag to prove the snippet is
        // interpolated as shell rather than treated as one executable path.
        let editor = try writeExecutable(
            "fake-editor", "#!/bin/sh\n[ \"$1\" = --flag ] || exit 5\nprintf 'added\\n' >> \"$2\"\n"
        )
        let result = try runWrapper(editor: "\(ShellQuote.single(editor)) --flag", text: "line\n\n\nmore\n")

        XCTAssertEqual(result.status, "0")
        XCTAssertEqual(result.text, "line\n\n\nmore\nadded\n")
    }

    func testReportsTheEditorsExitStatus() throws {
        let editor = try writeExecutable("quitter", "#!/bin/sh\nexit 3\n")
        let result = try runWrapper(editor: ShellQuote.single(editor), text: "x\n")

        XCTAssertEqual(result.status, "3")
        XCTAssertEqual(result.text, "x\n")
    }

    func testBakedPathIsWhatTheEditorSees() throws {
        let editor = try writeExecutable("path-echo", "#!/bin/sh\nprintf '%s' \"$PATH\" > \"$1\"\n")
        let result = try runWrapper(editor: ShellQuote.single(editor), text: "", path: "/custom/bin:/usr/bin")

        XCTAssertEqual(result.status, "0")
        XCTAssertEqual(result.text, "/custom/bin:/usr/bin")
    }

    func testMissingEditorReportsNonZero() throws {
        let result = try runWrapper(editor: "no-such-editor-anywhere", text: "x\n", path: "/usr/bin")

        XCTAssertEqual(result.status, "127")
    }
}
