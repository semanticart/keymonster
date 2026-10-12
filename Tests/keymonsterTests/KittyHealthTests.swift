import XCTest
@testable import keymonster

/// Finding kitty's socket from the process itself, and turning what the
/// environment reports into a diagnosis.
final class KittySocketTests: XCTestCase {
    func testPrefersAListeningKittySocket() {
        let candidates = [
            KittySocket.Candidate(path: "/var/run/other.sock", isListening: true),
            KittySocket.Candidate(path: "/tmp/mykitty-42", isListening: true),
            KittySocket.Candidate(path: "/tmp/kitty-peer", isListening: false)
        ]
        XCTAssertEqual(KittySocket.choose(from: candidates, pid: 42, exists: { _ in true }), "/tmp/mykitty-42")
    }

    func testFallsBackToAnyListeningSocketThenTheConventionalPath() {
        let other = [KittySocket.Candidate(path: "/var/run/other.sock", isListening: true)]
        XCTAssertEqual(KittySocket.choose(from: other, pid: 7, exists: { _ in true }), "/var/run/other.sock")
        XCTAssertEqual(
            KittySocket.choose(from: [], pid: 7, exists: { $0 == "/tmp/kitty-7" }), "/tmp/kitty-7"
        )
    }

    func testIgnoresSocketsThatDoNotExistAndNonListeningOnes() {
        let candidates = [
            KittySocket.Candidate(path: "/tmp/kitty-gone", isListening: true),
            KittySocket.Candidate(path: "/tmp/kitty-peer", isListening: false)
        ]
        XCTAssertNil(KittySocket.choose(from: candidates, pid: 7, exists: { _ in false }))
        XCTAssertNil(KittySocket.choose(from: candidates, pid: 7, exists: { $0 == "/tmp/kitty-peer" }))
    }

    /// The kernel really does report a process's listening unix sockets.
    func testFindsARealListeningSocketOfThisProcess() throws {
        let path = "/tmp/km-\(UUID().uuidString.prefix(8)).sock"
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            path.withCString { strncpy(buffer.baseAddress!.assumingMemoryBound(to: CChar.self), $0, buffer.count - 1) }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(descriptor, 1), 0)
        defer {
            close(descriptor)
            unlink(path)
        }

        let sockets = KittySocket.unixSockets(of: getpid())
        XCTAssertTrue(sockets.contains(KittySocket.Candidate(path: path, isListening: true)))
    }
}

final class KittyHealthTests: XCTestCase {
    private func lsOutput(windows: Int = 1) -> Data {
        let window = #"{"id": 1, "columns": 80, "lines": 24}"#
        let list = Array(repeating: window, count: windows).joined(separator: ",")
        return Data(#"[{"is_focused": false, "tabs": [{"is_active": true, "windows": [\#(list)]}]}]"#.utf8)
    }

    private func environment(
        pid: pid_t? = 1, socket: String? = "/tmp/kitty-1", kitten: Bool = true,
        listing: Data? = nil, tmux: String? = nil
    ) -> KittyHealth.Environment {
        KittyHealth.Environment(
            kittyPID: pid, socketPath: socket, kittenExists: kitten,
            run: socket == nil ? nil : { _ in listing },
            tmuxTerminalFeatures: tmux
        )
    }

    func testKittyNotRunningIsNotAnIssue() {
        let report = KittyHealth.check(environment(pid: nil))
        XCTAssertNil(report.firstIssue)
    }

    func testMissingSocketPointsAtListenOn() {
        let issue = KittyHealth.check(environment(socket: nil)).firstIssue
        XCTAssertEqual(issue?.level, .problem)
        XCTAssertTrue(issue?.detail.contains("listen_on") == true)
    }

    func testMissingKittenIsAProblem() {
        let report = KittyHealth.check(environment(kitten: false, listing: lsOutput()))
        XCTAssertEqual(report.firstIssue?.level, .problem)
    }

    func testRefusedConnectionPointsAtAllowRemoteControl() {
        let issue = KittyHealth.check(environment(listing: nil)).firstIssue
        XCTAssertEqual(issue?.level, .problem)
        XCTAssertTrue(issue?.detail.contains("allow_remote_control") == true)
    }

    func testHealthySetupHasNoIssue() {
        let report = KittyHealth.check(environment(listing: lsOutput()))
        XCTAssertNil(report.firstIssue)
        XCTAssertEqual(report.items.first?.level, .healthy)
    }

    func testSplitsWarn() {
        let issue = KittyHealth.check(environment(listing: lsOutput(windows: 2))).firstIssue
        XCTAssertEqual(issue?.level, .warning)
        XCTAssertEqual(issue?.title, "Splits")
    }

    func testTmuxWithoutHyperlinksWarnsAndWithItDoesNot() {
        let without = "terminal-features[0] xterm*:clipboard:title\nterminal-features[1] screen*:title"
        let warned = KittyHealth.check(environment(listing: lsOutput(), tmux: without))
        XCTAssertEqual(warned.firstIssue?.title, "tmux hyperlinks")

        let with = without + "\nterminal-features[2] xterm-kitty:hyperlinks"
        XCTAssertNil(KittyHealth.check(environment(listing: lsOutput(), tmux: with)).firstIssue)
        XCTAssertNil(KittyHealth.check(environment(listing: lsOutput(), tmux: nil)).firstIssue) // tmux not running
    }

    func testTmuxFeaturePatternsAreGlobs() {
        XCTAssertTrue(KittyHealth.tmuxForwardsHyperlinks(terminalFeatures: "terminal-features[0] xterm*:hyperlinks"))
        XCTAssertTrue(KittyHealth.tmuxForwardsHyperlinks(terminalFeatures: "terminal-features[0] *:RGB:hyperlinks"))
        XCTAssertFalse(KittyHealth.tmuxForwardsHyperlinks(terminalFeatures: "terminal-features[0] screen*:hyperlinks"))
        XCTAssertFalse(KittyHealth.tmuxForwardsHyperlinks(terminalFeatures: "terminal-features[0] xterm-kitty:RGB"))
        XCTAssertFalse(KittyHealth.tmuxForwardsHyperlinks(terminalFeatures: ""))
    }

    func testActiveTabWindowCountsIgnoreInactiveTabs() {
        let json = #"""
            [{"tabs": [{"is_active": false, "windows": [{}, {}, {}]}, {"is_active": true, "windows": [{}]}]}]
            """#
        XCTAssertEqual(KittyRemote.activeTabWindowCounts(inLS: Data(json.utf8)), [1])
        XCTAssertEqual(KittyRemote.activeTabWindowCounts(inLS: Data("nope".utf8)), [])
    }
}
