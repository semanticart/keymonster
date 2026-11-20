import SwiftUI

/// Settings rows for `AppSettings.largestScrollDomains`: sites where scroll
/// mode skips the pane pick and scrolls the biggest pane.
struct ScrollDomainsEditor: View {
    @ObservedObject var settings: AppSettings
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Always scroll the biggest pane on")
            Text("Browser sites with many nested scrollers (github.com). Covers subdomains.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(settings.largestScrollDomains, id: \.self) { domain in
                HStack {
                    Text(domain).font(.body.monospaced())
                    Spacer()
                    Button {
                        settings.largestScrollDomains.removeAll { $0 == domain }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("github.com", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(ScrollDomainRule.normalize(draft) == nil)
            }
        }
    }

    private func add() {
        guard let host = ScrollDomainRule.normalize(draft) else { return }
        if !settings.largestScrollDomains.contains(host) {
            settings.largestScrollDomains.append(host)
        }
        draft = ""
    }
}
