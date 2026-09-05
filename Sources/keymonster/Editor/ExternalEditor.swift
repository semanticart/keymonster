import Foundation

// The pure half of "Edit in Editor": how a field's text travels to a file and
// back, which editor to run, the wrapper script that runs it, and how each
// terminal app is asked to host that script. Nothing here touches AppKit or
// spawns anything, so it is all unit-tested; `ExternalEditorController` is the
// live plumbing around it.

/// The text's round trip through the file. Editors like vim insist on a
/// trailing newline at end of file, so a field whose text lacks one would come
/// back a newline longer every time. Add that one newline going out and remove
/// exactly it coming back; everything else — blank lines included, wherever they
/// are — is preserved byte for byte.
enum EditorRoundTrip {
    struct Outbound: Equatable {
        let fileContents: String
        /// True when a newline was appended, so `inbound` knows to strip one.
        let addedTrailingNewline: Bool
    }

    static func outbound(_ text: String) -> Outbound {
        if text.isEmpty || text.hasSuffix("\n") {
            return Outbound(fileContents: text, addedTrailingNewline: false)
        }
        return Outbound(fileContents: text + "\n", addedTrailingNewline: true)
    }

    static func inbound(_ fileContents: String, addedTrailingNewline: Bool) -> String {
        guard addedTrailingNewline, fileContents.hasSuffix("\n") else { return fileContents }
        return String(fileContents.dropLast())
    }
}

/// Which editor to run, in git's order of precedence: an explicit setting
/// wins, then the app-specific `$KEY_MONSTER_EDITOR` (git's `GIT_EDITOR`, for
/// an editor setup that only makes sense here — `nvim -c 'set ft=markdown'`),
/// then `$VISUAL`, then `$EDITOR`. The result is a shell snippet, not a path —
/// `code --wait` is a valid editor — exactly as git treats these variables.
enum EditorCommand {
    static let environmentVariable = "KEY_MONSTER_EDITOR"

    static func resolve(configured: String, environment: [String: String]) -> String? {
        let candidates = [
            configured,
            environment[environmentVariable] ?? "",
            environment["VISUAL"] ?? "",
            environment["EDITOR"] ?? ""
        ]
        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

enum ShellQuote {
    /// Single-quotes `value` for POSIX sh, escaping any embedded single quotes.
    static func single(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// The wrapper script an edit session runs, whether directly (`sh script`)
/// or as the program a terminal window hosts. It runs the editor on the text
/// file and then writes the editor's exit status next to it, which is how the
/// app learns the edit is over when the editor is off in a terminal window it
/// can't wait on. The status is written to a temp name and renamed, so a
/// poller never reads a half-written file.
///
/// The editor snippet is interpolated verbatim, as git does with `$EDITOR`, so
/// flags inside it work; the file paths are quoted. `PATH` is baked in because
/// a terminal app starts the script with the terminal's own environment, where
/// Homebrew and friends aren't on the path yet.
enum EditorWrapperScript {
    static let fileName = "edit.command"

    static func render(editor: String, textFile: String, statusFile: String, path: String?) -> String {
        var lines = [
            "#!/bin/sh",
            "# Written by Key Monster to run your editor on a text field's contents.",
            "# It is deleted once the edit is over; safe to delete by hand.",
            "cd \"$HOME\" 2>/dev/null"
        ]
        if let path, !path.isEmpty {
            lines.append("export PATH=\(ShellQuote.single(path))")
        }
        lines.append(contentsOf: [
            "\(editor) \(ShellQuote.single(textFile))",
            "status=$?",
            "printf '%s\\n' \"$status\" > \(ShellQuote.single(statusFile + ".tmp")) "
                + "&& /bin/mv -f \(ShellQuote.single(statusFile + ".tmp")) \(ShellQuote.single(statusFile))",
            "exit $status"
        ])
        return lines.joined(separator: "\n") + "\n"
    }
}

/// How to open a terminal app on the wrapper script. Every terminal has its
/// own idea of how to be told "run this program in a new window", so the ones
/// worth knowing are listed; anything else is handed the script as a document,
/// which works for any terminal that registers the `.command` type (Terminal
/// and iTerm2 do). `open` is used throughout: it goes through Launch Services,
/// so the window comes forward like a user-launched one, and `-n` starts a
/// fresh instance so `--args` is actually delivered when the app is already
/// running.
struct TerminalLaunch: Equatable {
    let executablePath: String
    let arguments: [String]

    static let openTool = "/usr/bin/open"

    static func make(bundleID: String, appPath: String, script: String) -> TerminalLaunch {
        let args: [String]
        switch bundleID {
        case "net.kovidgoyal.kitty":
            args = ["-na", appPath, "--args", script]
        case "org.alacritty":
            args = ["-na", appPath, "--args", "-e", script]
        case "com.github.wez.wezterm":
            args = ["-na", appPath, "--args", "start", "--", script]
        case "com.mitchellh.ghostty":
            args = ["-na", appPath, "--args", "-e", script]
        default:
            // Terminal.app, iTerm2, and anything else that opens .command files.
            args = ["-a", appPath, script]
        }
        return TerminalLaunch(executablePath: openTool, arguments: args)
    }
}
