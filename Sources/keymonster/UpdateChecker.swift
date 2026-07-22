import Foundation
import os.log

private let log = Logger(subsystem: "keymonster", category: "updates")

/// Asks GitHub's latest-release endpoint (on launch, then daily) whether a
/// newer version than the running one exists, and publishes it if so.
/// Deliberately not an auto-updater: nothing is downloaded or swapped in the
/// background — the app delegate just shows a menu item that opens the release
/// page, and the user stays in charge of the install.
@MainActor
final class UpdateChecker: ObservableObject {
    /// Where the update menu item sends the user. The releases page (rather
    /// than the bare DMG URL) so the notes are visible before downloading.
    static let releasesURL = URL(string: "https://github.com/semanticart/keymonster/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/semanticart/keymonster/releases/latest")!

    /// The newest released version, when it's ahead of the running one.
    @Published private(set) var availableVersion: String?

    private let currentVersion: String?
    private let isEnabled: @MainActor () -> Bool
    private let fetch: (URL) async throws -> Data
    private var timer: Timer?

    init(
        currentVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        isEnabled: @escaping @MainActor () -> Bool = { AppSettings.shared.checkForUpdates },
        fetch: @escaping (URL) async throws -> Data = { url in
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        }
    ) {
        self.currentVersion = currentVersion
        self.isEnabled = isEnabled
        self.fetch = fetch
    }

    /// Check once now and then daily. Bare `swift run` binaries carry no bundle
    /// version, so development builds never phone home or nag.
    func start() {
        guard currentVersion != nil else {
            log.info("no bundle version; update checks disabled")
            return
        }
        Task { await check() }
        let timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
            Task { @MainActor [weak self] in await self?.check() }
        }
        timer.tolerance = 60 * 60
        self.timer = timer
    }

    func check() async {
        guard let currentVersion else { return }
        // Opted out: never fetch, and retract any earlier answer so the menu
        // item disappears the moment the toggle is flipped off.
        guard isEnabled() else {
            availableVersion = nil
            return
        }
        do {
            let data = try await fetch(Self.apiURL)
            let release = try JSONDecoder().decode(LatestRelease.self, from: data)
            let latest = Self.version(fromTag: release.tagName)
            availableVersion = Self.isNewer(latest, than: currentVersion) ? latest : nil
            log.info("update check: latest \(latest), running \(currentVersion)")
        } catch {
            // Offline or rate-limited is normal for a background check; keep
            // whatever we last knew rather than flapping the menu item.
            log.info("update check failed: \(error)")
        }
    }

    static func version(fromTag tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Numeric per-component comparison of dotted versions, so "0.10.0" beats
    /// "0.9.1". Missing components count as 0 ("1.0" == "1.0.0"); non-numeric
    /// components also count as 0, which keeps oddball tags from ever looking
    /// newer than a real release.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = numericComponents(candidate)
        let rhs = numericComponents(current)
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func numericComponents(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}

/// The one field we need from GitHub's release payload.
private struct LatestRelease: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}
