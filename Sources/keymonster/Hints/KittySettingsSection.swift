import SwiftUI

/// The Mouse tab's status for kitty link hints: runs `KittyHealth` and lists
/// each step with what to fix. Kitty needs setup (a socket and remote control),
/// and from the outside "nothing happens" is indistinguishable from "no links
/// on screen" — this is where the difference is spelled out.
struct KittySettingsSection: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var report: KittyHealth?

    var body: some View {
        SettingsSection(
            header: "Kitty Link Hints",
            footer: "Click hints also label URLs and hyperlinks in kitty (including inside tmux), "
                + "and picking one opens it through kitty. Kitty needs `allow_remote_control yes` "
                + "and `listen_on unix:/tmp/kitty` in kitty.conf; restart it after changing them. "
                + "With a script set, file paths on screen (that exist; relative ones are "
                + "resolved against the window's directory) are hinted too, and picking one "
                + "runs the script with the absolute path as its argument. A `:line:column` "
                + "suffix arrives in $KEYMONSTER_LINE and $KEYMONSTER_COLUMN."
        ) {
            if let report {
                ForEach(Array(report.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: Self.symbol(for: item.level))
                            .foregroundStyle(Self.color(for: item.level))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).fontWeight(.medium)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                }
            } else {
                Text("Checking…").foregroundStyle(.secondary)
            }
            HStack {
                Text("File Path Script")
                Spacer()
                TextField("none (file paths aren't hinted)", text: $settings.filePathScript)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(width: 260)
            }
            HStack {
                Button("Check Again") { refresh() }
                Spacer()
            }
        }
        .onAppear { refresh() }
    }

    private func refresh() {
        report = nil
        Task.detached {
            let result = KittyHealth.live()
            await MainActor.run { report = result }
        }
    }

    private static func symbol(for level: KittyHealth.Level) -> String {
        switch level {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .problem: return "xmark.octagon.fill"
        }
    }

    private static func color(for level: KittyHealth.Level) -> Color {
        switch level {
        case .healthy: return .green
        case .warning: return .orange
        case .problem: return .red
        }
    }
}
