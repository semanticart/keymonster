import Foundation
import JavaScriptCore
import os.log

private let log = Logger(subsystem: "keymonster", category: "palette.providers")

/// Something that turns the finder's query into zero or more extra rows, ahead
/// of the fuzzy-ranked bookmarks. Results are `Bookmark`s so the finder's row,
/// open, and selection code needs no second path; the view model reassigns
/// their ids, so a provider may number them however it likes.
protocol SuggestionProvider {
    func suggestions(for query: String) -> [Bookmark]
}

/// A user script run in-process with JavaScriptCore. The script defines a
/// global `suggest(query)` that returns an array of `{title, url}` objects (an
/// empty array or `undefined` for "nothing to say"):
///
///     function suggest(q) {
///       if (!/^[0-9a-f]{8}-[0-9a-f]{4}-/i.test(q)) return []
///       return [{ title: "Order " + q, url: "https://admin.example.com/orders/" + q }]
///     }
///
/// Scripts see only the JS standard library — no filesystem, network, or shell.
/// A script that fails to load, throws, or returns junk contributes nothing
/// rather than breaking the finder; the failure is logged (a runtime error once
/// per distinct message, since `suggest` runs on every keystroke) and the last
/// one is kept in `lastError`.
final class ScriptedProvider: SuggestionProvider {
    /// Why a script couldn't be loaded.
    struct LoadError: Error, Equatable, CustomStringConvertible {
        let description: String
    }

    let name: String
    private(set) var lastError: String?
    private var lastLoggedError: String?
    private let context: JSContext

    /// Throws a `LoadError` when `source` doesn't evaluate or doesn't define
    /// a `suggest` function.
    init(name: String, source: String) throws {
        guard let context = JSContext() else { throw LoadError(description: "could not create a JavaScript context") }
        var loadError: String?
        context.exceptionHandler = { _, exception in loadError = Self.describe(exception) }
        context.evaluateScript(source)
        if let loadError { throw LoadError(description: loadError) }
        guard context.objectForKeyedSubscript("suggest").isObject else {
            throw LoadError(description: "does not define a suggest(query) function")
        }

        self.name = name
        self.context = context
        context.exceptionHandler = { [weak self] _, exception in
            self?.lastError = Self.describe(exception)
        }
    }

    /// "Error: boom (line 3)" — the line makes a failure findable in the script.
    private static func describe(_ exception: JSValue?) -> String {
        guard let exception else { return "unknown error" }
        let message = exception.toString() ?? "unknown error"
        if let line = exception.objectForKeyedSubscript("line"), line.isNumber {
            return "\(message) (line \(line.toInt32()))"
        }
        return message
    }

    func suggestions(for query: String) -> [Bookmark] {
        lastError = nil
        let result = context.objectForKeyedSubscript("suggest").call(withArguments: [query])
        if lastError == nil, let result, !result.isUndefined, !result.isNull, !result.isArray {
            lastError = "suggest must return an array of {title, url}"
        }
        logRuntimeErrorIfNew()
        guard let items = result?.toArray() else { return [] }

        var bookmarks: [Bookmark] = []
        for case let item as [String: Any] in items {
            guard let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespaces),
                  let url = (item["url"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !title.isEmpty, !url.isEmpty else { continue }
            bookmarks.append(Bookmark(id: bookmarks.count, title: title, url: url))
        }
        return bookmarks
    }

    private func logRuntimeErrorIfNew() {
        guard let lastError else {
            lastLoggedError = nil
            return
        }
        guard lastError != lastLoggedError else { return }
        lastLoggedError = lastError
        log.error("provider \(self.name, privacy: .public) failed: \(lastError, privacy: .public)")
    }
}

/// Where provider scripts live: every `*.js` file in `providers/` beside the
/// bookmarks CSV. Loaded fresh each time the finder opens, like the CSV.
enum ProviderStore {
    static let directoryName = "providers"

    static func defaultDirectory() -> URL {
        BookmarksStore.defaultURL()
            .deletingLastPathComponent()
            .appendingPathComponent(directoryName)
    }

    /// The loadable providers in `directory`, in filename order. A missing
    /// directory yields none; a script that can't be read or doesn't load is
    /// skipped and reported to `onFailure` (file name, reason) — by default,
    /// to the unified log.
    static func load(
        from directory: URL = defaultDirectory(),
        onFailure: (String, String) -> Void = { name, reason in
            log.error("provider \(name, privacy: .public) not loaded: \(reason, privacy: .public)")
        }
    ) -> [ScriptedProvider] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var providers: [ScriptedProvider] = []
        let scripts = files
            .filter { $0.pathExtension == "js" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in scripts {
            let name = file.lastPathComponent
            guard let source = try? String(contentsOf: file, encoding: .utf8) else {
                onFailure(name, "could not be read as UTF-8 text")
                continue
            }
            do {
                providers.append(try ScriptedProvider(name: name, source: source))
            } catch {
                onFailure(name, "\(error)")
            }
        }
        return providers
    }
}
