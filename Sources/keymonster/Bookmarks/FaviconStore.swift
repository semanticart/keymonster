import AppKit

/// Fetches and disk-caches favicons for bookmarked sites, keyed by host.
/// Tries each host's own `/favicon.ico` first; if that's missing or invalid,
/// falls back to fetching the homepage and following the `<link rel="icon">`
/// it declares (see `FaviconLinkParser`) — needed for sites built on
/// Webflow, Squarespace, and similar, which only declare an icon that way,
/// often on a different host/CDN. No third-party favicon-resolution service
/// either way, so coverage is still best-effort: a site with neither has no
/// cached favicon, and its row falls back to a generic glyph. Cached
/// indefinitely; favicons rarely change and there's no user-facing way to
/// force a refresh.
@MainActor
final class FaviconStore: ObservableObject {
    static let shared = FaviconStore()

    /// Decoded favicons, keyed by lowercased host. A missing entry means
    /// either never requested, still loading, or the fetch failed/found
    /// nothing — those three aren't distinguished, since a row shows the same
    /// fallback glyph either way.
    @Published private(set) var images: [String: NSImage] = [:]

    private var inFlight: Set<String> = []
    private let cacheDirectory: URL
    /// The network edge, injectable for tests. Returns nil on any failure
    /// (offline, 404, non-2xx) rather than throwing — a missing favicon isn't
    /// an error worth reporting anywhere.
    private let fetchData: @MainActor (URL) async -> Data?

    init(
        cacheDirectory: URL = FaviconStore.defaultCacheDirectory(),
        fetchData: @escaping @MainActor (URL) async -> Data? = FaviconStore.defaultFetch
    ) {
        self.cacheDirectory = cacheDirectory
        self.fetchData = fetchData
    }

    static func defaultCacheDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("keymonster")
            .appendingPathComponent("favicons")
    }

    private static func defaultFetch(_ url: URL) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        return data
    }

    /// The host a bookmark's favicon is keyed by, or nil for an unparseable url.
    static func host(of urlString: String) -> String? {
        URL(string: urlString)?.host?.lowercased()
    }

    /// Loads the favicon for `urlString`'s host — from memory, then disk,
    /// then a network fetch — publishing it via `images` once available. Safe
    /// to call repeatedly (e.g. once per row appearance): a host that's
    /// already cached or already being fetched is a no-op.
    func request(for urlString: String) async {
        guard let host = Self.host(of: urlString) else { return }
        guard images[host] == nil, !inFlight.contains(host) else { return }
        inFlight.insert(host)
        defer { inFlight.remove(host) }

        if let cached = loadFromDisk(host: host) {
            images[host] = cached
            return
        }
        guard let fetched = await fetchIcon(host: host) else { return }
        saveToDisk(host: host, data: fetched.data)
        images[host] = fetched.image
    }

    /// `/favicon.ico` first; if that's missing or isn't a decodable image,
    /// fetches the homepage and follows its declared `<link rel="icon">`.
    private func fetchIcon(host: String) async -> (image: NSImage, data: Data)? {
        guard let root = URL(string: "https://\(host)/") else { return nil }
        // .absoluteURL: a bare URL(string:relativeTo:) keeps its base and
        // relative parts separate rather than resolving eagerly, so it won't
        // == an absolute URL literal even when .absoluteString matches.
        if let direct = URL(string: "favicon.ico", relativeTo: root)?.absoluteURL,
           let data = await fetchData(direct), let image = NSImage(data: data) {
            return (image, data)
        }
        guard let html = await fetchData(root), let text = String(data: html, encoding: .utf8),
              let iconURL = FaviconLinkParser.iconURL(in: text, pageURL: root),
              let data = await fetchData(iconURL), let image = NSImage(data: data) else {
            return nil
        }
        return (image, data)
    }

    private func cacheFile(for host: String) -> URL {
        cacheDirectory.appendingPathComponent(host).appendingPathExtension("ico")
    }

    private func loadFromDisk(host: String) -> NSImage? {
        guard let data = try? Data(contentsOf: cacheFile(for: host)) else { return nil }
        return NSImage(data: data)
    }

    private func saveToDisk(host: String, data: Data) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: cacheFile(for: host))
    }
}
