import AppKit
import Foundation

/// Records script-shortcut failures to a plain-text log file and publishes the
/// most recent one, so Settings can show what went wrong and offer to open the
/// log (Console.app handles .log files).
@MainActor
final class ScriptLog: ObservableObject {
    static let shared = ScriptLog()

    struct Failure: Equatable {
        let script: String
        let detail: String
        let date: Date
    }

    /// The most recent failure this session; drives the notice in Settings.
    @Published private(set) var lastFailure: Failure?

    let fileURL: URL

    init(fileURL: URL = ScriptLog.defaultURL()) {
        self.fileURL = fileURL
    }

    /// ~/Library/Logs/keymonster/scripts.log
    static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/keymonster/scripts.log")
    }

    func record(script: String, detail: String, date: Date = Date()) {
        lastFailure = Failure(script: script, detail: detail, date: date)
        append(line: "\(date.ISO8601Format()) \(script): \(detail)\n")
    }

    func open() {
        NSWorkspace.shared.open(fileURL)
    }

    private func append(line: String) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
