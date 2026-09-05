import AppKit
import Combine
import SwiftUI
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints.secureinput.diagnostics")

/// Polls `SecureInput.current()` on a timer and keeps a running log of state
/// changes. Key Monster's focus-based capture is immune to Secure Keyboard
/// Entry, so this window is informational: it shows the system state live and
/// helps find which app is holding secure input (by elimination) when some
/// *other* tool is starved by it. It only records a new row when the state
/// actually changes, so the log stays short across long runs.
@MainActor
final class SecureInputMonitor: ObservableObject {
    struct Event: Identifiable {
        let id = UUID()
        let time: Date
        let description: String
        let secureInputOn: Bool
    }

    @Published private(set) var current: SecureInput.Snapshot = .free
    @Published private(set) var events: [Event] = []
    @Published private(set) var accessibilityTrusted = true

    private var timer: Timer?
    private var lastDescription: String?

    /// Begin polling (idempotent). The window starts this when it opens.
    func start() {
        guard timer == nil else { return }
        log.debug("secure input monitor started")
        poll()
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stop polling. The window stops this on close so we don't poll forever.
    func stop() {
        guard timer != nil else { return }
        log.debug("secure input monitor stopped")
        timer?.invalidate()
        timer = nil
    }

    func clear() {
        events.removeAll()
        lastDescription = nil
    }

    /// The whole log as text, for the Copy button.
    func logText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return events.reversed()
            .map { "\(formatter.string(from: $0.time))  \($0.description)" }
            .joined(separator: "\n")
    }

    #if DEBUG
    /// Seed representative state for headless screenshots (`secinput shot`), so a
    /// captured window shows a populated log without waiting for real events.
    func debugSeed() {
        accessibilityTrusted = true
        current = SecureInput.Snapshot(
            enabled: true, holderPID: 100, holderName: "Google Chrome", holderBundleID: "com.google.Chrome",
            frontmostPID: 100, frontmostName: "Google Chrome", screenLocked: false
        )
        let now = Date()
        events = [
            Event(time: now, description: Self.describe(current), secureInputOn: true),
            Event(time: now.addingTimeInterval(-8),
                  description: "On — reported “Slack”, but that's just the frontmost app (unreliable)",
                  secureInputOn: true),
            Event(time: now.addingTimeInterval(-20),
                  description: "Secure Keyboard Entry is off", secureInputOn: false)
        ]
    }
    #endif

    private func poll() {
        accessibilityTrusted = Paster.isTrusted
        let snapshot = SecureInput.current()
        current = snapshot
        let description = Self.describe(snapshot)
        guard description != lastDescription else { return }
        lastDescription = description
        events.insert(
            Event(time: Date(), description: description, secureInputOn: snapshot.enabled), at: 0
        )
        if events.count > 200 { events.removeLast(events.count - 200) }
    }

    /// A one-line, human-readable summary of a snapshot — also the change key, so
    /// two snapshots that read the same don't add a row. Narrates the system
    /// state only: secure input never affects Key Monster's modes.
    static func describe(_ snapshot: SecureInput.Snapshot) -> String {
        guard snapshot.enabled else { return "Secure Keyboard Entry is off" }
        if snapshot.screenLocked {
            return "On — screen locked (holder masked as loginwindow)"
        }
        let holder = snapshot.holderName
            ?? snapshot.holderPID.map { "pid \($0)" }
            ?? "unknown app"
        if snapshot.holderIsFrontmost {
            return "On — reported “\(holder)”, but that's just the frontmost app (unreliable)"
        }
        return "On — reported “\(holder)” (background process — worth investigating)"
    }
}

/// The Secure Keyboard Entry window, opened from the menu bar. Shows the live
/// on/off state and a change log, with instructions for finding the holder by
/// quitting suspects one at a time — useful when some other tool is starved by
/// secure input; Key Monster itself never is.
struct SecureInputDiagnosticsView: View {
    @ObservedObject var monitor: SecureInputMonitor

    private var secureInputOn: Bool { monitor.current.enabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusBanner

            permissions

            Text("""
                The named app is usually a red herring — macOS reports whichever app is \
                frontmost, not the one that turned Secure Keyboard Entry on. To find the real \
                culprit, quit suspects one at a time: keystroke viewers like Karabiner-Elements' \
                Event Viewer; Chromium apps (Chrome, Slack, VS Code) with a focused password \
                field; password managers; Terminal's Secure Keyboard Entry. When this flips to \
                green, the app you just quit was holding it.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                Text("Change log")
                    .font(.headline)
                Spacer()
                Button("Copy") { copyLog() }
                    .disabled(monitor.events.isEmpty)
                Button("Clear") { monitor.clear() }
                    .disabled(monitor.events.isEmpty)
            }

            logList
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 420)
    }

    private var permissions: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(monitor.accessibilityTrusted ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
            Text("Accessibility").font(.callout.weight(.medium))
            Text(monitor.accessibilityTrusted ? "Granted" : "Not granted")
                .font(.callout)
                .foregroundStyle(monitor.accessibilityTrusted ? Color.secondary : Color.orange)
            Spacer(minLength: 8)
            Text("the only permission the modes need")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    private var statusBanner: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(secureInputOn ? Color.orange : Color.green)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(bannerTitle)
                    .font(.title2.weight(.semibold))
                Text(SecureInputMonitor.describe(monitor.current))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill((secureInputOn ? Color.orange : Color.green).opacity(0.12))
        )
    }

    private var bannerTitle: String {
        secureInputOn
            ? "Secure Keyboard Entry is on — Key Monster is unaffected"
            : "Secure Keyboard Entry is off"
    }

    private var logList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if monitor.events.isEmpty {
                    Text("Watching… state changes will appear here.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                }
                ForEach(monitor.events) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(event.time, format: .dateTime.hour().minute().second())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Circle()
                            .fill(event.secureInputOn ? Color.orange : Color.green)
                            .frame(width: 7, height: 7)
                        Text(event.description)
                            .font(.callout)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(monitor.logText(), forType: .string)
    }
}
