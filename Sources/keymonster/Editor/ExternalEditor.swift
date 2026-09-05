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

/// A field's whole text as read through its paragraphs, for editors whose
/// `AXValue` is lossy. Chromium (Chrome, Electron apps like Slack) exposes a
/// rich-text editable as an `AXTextArea` whose value is its block children
/// joined by newlines — except that an *empty* paragraph contributes nothing,
/// so a blank line between two paragraphs reads back as a single newline. The
/// paragraphs themselves are still there in the tree, one child group each,
/// so the blank lines can be put back by reading those instead. Captured
/// against Slack, 2026-09-04.
///
/// The reconstruction is only trusted when it agrees with the value on every
/// non-blank line and adds newlines; anything else (inline content the leaves
/// don't carry, a shape this wasn't written for) falls back to the value as
/// the app reported it — today's behaviour.
enum ParagraphText {
    /// One string per direct child of `element`: its leaf text concatenated,
    /// or "" for a childless, valueless child (an empty paragraph). Nil when
    /// the tree is bigger than `limit` nodes, since walking a whole document
    /// for this isn't worth it.
    static func paragraphs<Tree: AXTextTree>(
        of element: Tree.Element, in tree: Tree, limit: Int = 4000
    ) -> [String]? {
        var budget = limit
        var result: [String] = []
        for child in tree.children(of: element) {
            guard let text = leafText(of: child, in: tree, budget: &budget) else { return nil }
            result.append(text)
        }
        return result
    }

    private static func leafText<Tree: AXTextTree>(
        of element: Tree.Element, in tree: Tree, budget: inout Int
    ) -> String? {
        budget -= 1
        guard budget >= 0 else { return nil }
        let children = tree.children(of: element)
        if children.isEmpty { return tree.stringValue(of: element) ?? "" }
        var text = ""
        for child in children {
            guard let piece = leafText(of: child, in: tree, budget: &budget) else { return nil }
            text += piece
        }
        return text
    }

    /// `value` with the blank lines its paragraphs show it dropped, or `value`
    /// untouched when the paragraphs don't tell that exact story.
    static func restoringBlankLines(in value: String, paragraphs: [String]?) -> String {
        guard let paragraphs, !paragraphs.isEmpty else { return value }
        let joined = paragraphs.joined(separator: "\n")
        guard newlineCount(joined) > newlineCount(value),
              nonBlankLines(joined) == nonBlankLines(value) else {
            return value
        }
        return joined
    }

    private static func newlineCount(_ text: String) -> Int {
        text.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
    }

    private static func nonBlankLines(_ text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
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
/// and iTerm2 do; kitty does too, but asks for confirmation every time).
///
/// Both go through Launch Services (`NSWorkspace`), so the window comes forward
/// like a user-launched one. The listed terminals only take command-line
/// arguments at process start, so they get a fresh instance of the app — a
/// running one would just be activated and the arguments dropped. That instance
/// is ours, and lingers with no windows once the editor exits, so the app may
/// quit it afterwards (see `ExternalEditorController`); a document open reuses
/// whatever the user already has running and must be left alone.
enum TerminalLaunch: Equatable {
    /// Start a new instance of the app with these arguments.
    case newInstance(arguments: [String])
    /// Ask the (possibly running) app to open the script as a document.
    case document

    static func make(bundleID: String, script: String) -> TerminalLaunch {
        switch bundleID {
        case "net.kovidgoyal.kitty":
            return .newInstance(arguments: [script])
        case "org.alacritty":
            return .newInstance(arguments: ["-e", script])
        case "com.github.wez.wezterm":
            return .newInstance(arguments: ["start", "--", script])
        case "com.mitchellh.ghostty":
            return .newInstance(arguments: ["-e", script])
        default:
            // Terminal.app, iTerm2, and anything else that opens .command files.
            return .document
        }
    }
}
