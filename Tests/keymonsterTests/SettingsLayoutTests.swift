import XCTest
import SwiftUI
import AppKit
@testable import keymonster

/// Settings tabs have no scrolling: whatever height the tab hands its content
/// is what the content gets. A subview that collapses when the height is tight
/// silently truncates its text instead, so these pin the "won't collapse" part.
@MainActor
final class SettingsLayoutTests: XCTestCase {
    private static let settingsWidth: CGFloat = 500

    private func height(footer: String, proposedHeight: CGFloat) -> CGFloat {
        let section = SettingsSection(footer: footer) {
            Text("A row")
        }
        .frame(width: Self.settingsWidth)
        let host = NSHostingController(rootView: section)
        return host.sizeThatFits(
            in: NSSize(width: Self.settingsWidth, height: proposedHeight)
        ).height
    }

    /// A multi-line footer keeps every wrapped line even when the space offered
    /// is far too small; without that it collapsed to one truncated line
    /// ("…Failures are written…") and hid the log path from the Scripts tab.
    func testLongFooterKeepsEveryLineWhenSpaceIsTight() {
        let footer = String(repeating: "Failures are written to "
            + "~/Library/Logs/keymonster/scripts.log. ", count: 4)
        let ideal = height(footer: footer, proposedHeight: .greatestFiniteMagnitude)
        let squeezed = height(footer: footer, proposedHeight: 40)
        XCTAssertEqual(squeezed, ideal, accuracy: 1)
    }
}
