import Foundation

/// A built-in `SuggestionProvider` that offers installed applications as
/// palette rows. JavaScript providers can't see the filesystem, so this one is
/// native. Each row's url is the app's path, which the finder already opens and
/// icons like any other local path — no icon plumbing needed.
final class ApplicationsProvider: SuggestionProvider {
    static let defaultDirectories = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        ("~/Applications" as NSString).expandingTildeInPath
    ].map { URL(fileURLWithPath: $0, isDirectory: true) }

    /// Most rows one query may add, so a short query can't bury the bookmarks.
    static let maxResults = 5

    /// Applications rank below scripts and bookmarks.
    let trailsBookmarks = true

    private let apps: [(name: String, path: String)]

    init(apps: [(name: String, path: String)]) {
        self.apps = apps
    }

    convenience init(directories: [URL] = ApplicationsProvider.defaultDirectories) {
        self.init(apps: Self.scan(directories))
    }

    /// The `.app` bundles directly inside `directories`, named without the
    /// extension. A name found in several directories keeps its first path.
    static func scan(_ directories: [URL]) -> [(name: String, path: String)] {
        var seen = Set<String>()
        var apps: [(name: String, path: String)] = []
        for directory in directories {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )) ?? []
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                if seen.insert(name.lowercased()).inserted { apps.append((name, url.path)) }
            }
        }
        return apps
    }

    func suggestions(for query: String) -> [Bookmark] {
        struct Match { let score: Int; let index: Int; let app: (name: String, path: String) }
        let matches = apps.enumerated().compactMap { index, app -> Match? in
            FuzzyMatch.scoreWords(app.name, query: query).map { Match(score: $0, index: index, app: app) }
        }
        return matches
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
            .prefix(Self.maxResults)
            .enumerated()
            .map { Bookmark(id: $0.offset, title: $0.element.app.name, url: $0.element.app.path) }
    }
}
