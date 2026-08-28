#!/usr/bin/env swift
// diagnose-secure-input.swift — standalone Secure Keyboard Entry diagnostic.
//
// Copy this single file to any Mac (needs Xcode or the Command Line Tools) and:
//
//     swift diagnose-secure-input.swift          # full report, then live monitor
//     swift diagnose-secure-input.swift once     # report once and exit
//
// No Accessibility / Input Monitoring grants needed — everything here is
// unprivileged.
//
// What it knows that the obvious approach doesn't (verified empirically in
// keymonster development, 2026-08):
//   * `kCGSSessionSecureInputPID` names the app currently RECEIVING secure
//     input — i.e. whatever is frontmost — not the process that enabled it.
//     The script proves this per-machine with a short probe, then tells you to
//     find the real holder by elimination in the live monitor.
//   * While the screen is locked the pid masks as `loginwindow`.
//   * A "keys don't reach the app" symptom is often NOT secure input at all
//     but a missing Input Monitoring grant (separate from Accessibility), so
//     the report reminds you to check both.

import AppKit
import Carbon.HIToolbox

// MARK: - Sampling

struct Sample {
    var enabled: Bool
    var reportedPID: Int?
    var reportedName: String?
    var frontmostPID: pid_t?
    var frontmostName: String?
    var screenLocked: Bool
}

/// Name a pid even when it's not a GUI app (NSRunningApplication only covers
/// those); fall back to `ps` so CLI holders like `pinentry` still get named.
func processName(pid: Int) -> String? {
    if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
        return app.localizedName ?? app.bundleIdentifier
    }
    let lookup = Process()
    lookup.executableURL = URL(fileURLWithPath: "/bin/ps")
    lookup.arguments = ["-p", String(pid), "-o", "comm="]
    let pipe = Pipe()
    lookup.standardOutput = pipe
    lookup.standardError = Pipe()
    guard (try? lookup.run()) != nil else { return nil }
    lookup.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return (out?.isEmpty == false) ? out : nil
}

func sample() -> Sample {
    let frontmost = NSWorkspace.shared.frontmostApplication
    let locked = frontmost?.bundleIdentifier == "com.apple.loginwindow"
    let enabled = IsSecureEventInputEnabled()
    var pid: Int?
    if enabled {
        pid = (CGSessionCopyCurrentDictionary() as? [String: Any])?["kCGSSessionSecureInputPID"] as? Int
    }
    return Sample(
        enabled: enabled,
        reportedPID: pid,
        reportedName: pid.flatMap { $0 > 0 ? processName(pid: $0) : nil },
        frontmostPID: frontmost?.processIdentifier,
        frontmostName: frontmost?.localizedName,
        screenLocked: locked
    )
}

func describe(_ state: Sample) -> String {
    guard state.enabled else { return "OFF — keys flow normally" }
    if state.screenLocked { return "ON — screen locked (holder masked as loginwindow)" }
    let name = state.reportedName ?? "?"
    let pid = state.reportedPID.map(String.init) ?? "?"
    if let reported = state.reportedPID, let front = state.frontmostPID, reported == Int(front) {
        return "ON — reported \(name) (pid \(pid)) == frontmost app; name is UNRELIABLE"
    }
    return "ON — reported \(name) (pid \(pid)), a background process — investigate this one"
}

/// Pump the runloop (so AppKit's frontmost-app state refreshes) for `seconds`.
func spin(_ seconds: TimeInterval) {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
}

func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: Date())
}

// MARK: - Helper checks

func defaultsValue(domain: String, key: String) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["read", domain, key]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    guard (try? process.run()) != nil else { return nil }
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

struct SuspectPattern {
    var pattern: String
    var why: String

    init(_ pattern: String, _ why: String) {
        self.pattern = pattern
        self.why = why
    }
}

struct Suspect {
    var name: String
    var pid: pid_t
    var why: String
}

/// Running apps that are known to hold Secure Keyboard Entry (or commonly get
/// blamed for it). Matched loosely by name/bundle id.
let suspectPatterns: [SuspectPattern] = [
    SuspectPattern("terminal", "menu has a Secure Keyboard Entry toggle"),
    SuspectPattern("iterm", "menu has a Secure Keyboard Entry toggle"),
    SuspectPattern("karabiner", "EventViewer holds it while open"),
    SuspectPattern("1password", "password manager — holds it around autofill/unlock"),
    SuspectPattern("bitwarden", "password manager"),
    SuspectPattern("keepassx", "password manager"),
    SuspectPattern("lastpass", "password manager"),
    SuspectPattern("dashlane", "password manager"),
    SuspectPattern("chrome", "Chromium: holds it while a password field has focus"),
    SuspectPattern("brave", "Chromium: holds it while a password field has focus"),
    SuspectPattern("edge", "Chromium: holds it while a password field has focus"),
    SuspectPattern("electron", "Chromium: holds it while a password field has focus"),
    SuspectPattern("slack", "Electron: holds it while a password field has focus"),
    SuspectPattern("discord", "Electron: holds it while a password field has focus"),
    SuspectPattern("code", "Electron: holds it while a password field has focus"),
    SuspectPattern("music", "known to hold it indefinitely on some systems"),
    SuspectPattern("pinentry", "GPG passphrase prompt (may be a stuck background process)"),
    SuspectPattern("citrix", "remote-desktop clients often hold it")
]

func runningSuspects() -> [Suspect] {
    NSWorkspace.shared.runningApplications.compactMap { app in
        let haystack = "\(app.localizedName ?? "") \(app.bundleIdentifier ?? "")".lowercased()
        guard let hit = suspectPatterns.first(where: { haystack.contains($0.pattern) }) else { return nil }
        return Suspect(
            name: app.localizedName ?? app.bundleIdentifier ?? "?",
            pid: app.processIdentifier,
            why: hit.why
        )
    }
}

// MARK: - Report

/// Demonstrate, on this machine, that the reported holder pid tracks the
/// frontmost app rather than the process that enabled secure input — or catch
/// the rare useful case where it points at a background process.
func runAttributionProbe() {
    print("""

    Probing for 4s whether the reported pid just tracks the frontmost app
    (switch apps now if you can — Cmd-Tab a couple of times)...
    """)
    var reportedPIDs = Set<Int>()
    var alwaysFrontmost = true
    let end = Date(timeIntervalSinceNow: 4)
    while Date() < end {
        let probe = sample()
        if let reported = probe.reportedPID {
            reportedPIDs.insert(reported)
            if probe.frontmostPID.map({ Int($0) != reported }) ?? true { alwaysFrontmost = false }
        }
        spin(0.2)
    }
    if alwaysFrontmost {
        print("""
        → Reported pid matched the frontmost app the whole time. As expected,
          macOS is naming the RECEIVER of secure input, not the process that
          enabled it. Ignore the name; use the elimination monitor below.
        """)
    } else {
        let names = reportedPIDs.sorted().map { "\(processName(pid: $0) ?? "?") (pid \($0))" }
        print("""
        → Reported pid pointed at a NON-frontmost process at least once:
          \(names.joined(separator: ", "))
          That background process is a strong culprit candidate.
        """)
    }
}

func fullReport() {
    print("Secure Keyboard Entry diagnostic — \(Date())")
    print(String(repeating: "=", count: 64))

    let state = sample()
    print("\nCurrent state: \(describe(state))")
    if let name = state.frontmostName {
        print("Frontmost app: \(name) (pid \(state.frontmostPID.map(String.init) ?? "?"))")
    }

    // The reported-pid caveat, proven live on this machine when possible.
    if state.enabled && !state.screenLocked {
        runAttributionProbe()
    }

    // Terminal emulators can persist the toggle across launches — check prefs
    // directly, since that's a one-command fix.
    print("\nTerminal-emulator toggles (persist across restarts):")
    let term = defaultsValue(domain: "com.apple.Terminal", key: "SecureKeyboardEntry")
    let iterm = defaultsValue(domain: "com.googlecode.iterm2", key: "Secure Input")
    let termFlag = term == "1" ? "   ← ENABLED: Terminal menu ▸ Secure Keyboard Entry" : ""
    let itermFlag = iterm == "1" ? "   ← ENABLED: iTerm2 menu ▸ Secure Keyboard Entry" : ""
    print("  Terminal.app  SecureKeyboardEntry = \(term ?? "unset")\(termFlag)")
    print("  iTerm2        Secure Input        = \(iterm ?? "unset/not installed")\(itermFlag)")

    let suspects = runningSuspects()
    if !suspects.isEmpty {
        print("\nRunning apps known to hold (or get blamed for) secure input:")
        for suspect in suspects {
            print("  \(suspect.name) (pid \(suspect.pid)) — \(suspect.why)")
        }
    }

    print("""

    Not-actually-secure-input reminder: if keymonster shows its overlay but
    ignores keys, ALSO verify BOTH permissions in System Settings ▸ Privacy &
    Security for the keymonster app:
      • Accessibility     (runs the event tap)
      • Input Monitoring  (reads the keystrokes — the one that's easy to miss)
    Granting one does not grant the other, and a missing Input Monitoring
    grant looks exactly like a Secure Keyboard Entry block.
    """)
}

// MARK: - Monitor (elimination mode)

func monitor() {
    print("""

    Live monitor — quit suspects ONE AT A TIME (start with the list above:
    Terminal/iTerm toggle, Karabiner EventViewer, password managers, Chromium
    apps with a focused password field, Music). When the state flips to OFF,
    the thing you just quit was the holder. Ctrl-C to stop.
    \(String(repeating: "-", count: 64))
    """)
    var last: String?
    while true {
        let line = describe(sample())
        if line != last {
            print("\(timestamp())  \(line)")
            if last != nil && line.hasPrefix("OFF") {
                print("\(timestamp())  ✓ Released — whatever you just quit/closed was the holder.")
            }
            last = line
        }
        spin(0.3)
    }
}

// MARK: - Main

setbuf(stdout, nil)
fullReport()
if !CommandLine.arguments.contains("once") {
    monitor()
}
