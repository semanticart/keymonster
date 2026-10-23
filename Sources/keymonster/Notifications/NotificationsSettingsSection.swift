import SwiftUI

/// The Notifications tab: the dismiss shortcut and what it does.
struct NotificationsSettingsTab: View {
    @Binding var shortcut: Shortcut?
    let isConflicting: Bool
    let showAccessibilityNotice: Bool

    var body: some View {
        SettingsTabView(description: "Clear notification banners without reaching for the "
            + "mouse. Requires Accessibility permission.") {
            section
        }
    }

    private var section: some View {
        ShortcutSettingSection(
            title: "Dismiss Notifications",
            shortcut: $shortcut,
            isConflicting: isConflicting,
            showAccessibilityNotice: showAccessibilityNotice,
            header: "Dismiss",
            footer: "Dismiss every notification on screen at once — banners, and "
                + "stacks in the open Notification Center. Does nothing when there "
                + "are none. Works in any system language."
        )
    }
}
