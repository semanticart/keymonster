import SwiftUI

/// The Mouse tab's opt-in hint experiments. Off by default; each toggle is
/// something we're still judging by eye on real apps.
struct ExperimentalHintsSection: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsSection(
            header: "Experimental",
            footer: "Center click-hint labels over small targets such as icon buttons "
                + "and checkboxes, instead of hanging them off the top-left corner. "
                + "Wide targets keep the corner."
        ) {
            SettingsToggleRow(title: "Center hints on small targets", isOn: $settings.centerSmallHints)
        }
    }
}
