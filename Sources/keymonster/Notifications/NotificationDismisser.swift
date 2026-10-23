import AppKit
import ApplicationServices
import os.log

private let log = Logger(subsystem: "keymonster", category: "notifications")

/// The live edge of notification dismissal: reads Notification Center's
/// accessibility tree and hands it to `NotificationDismissal`.
@MainActor
enum NotificationDismisser {
    static let bundleID = "com.apple.notificationcenterui"

    /// Read once: the loctable is large and fixed for the life of the process.
    private static let dismissNames = DismissNames.localized()

    /// Notification Center is a busy system agent; bound how long a single AX
    /// call may block the main thread.
    private static let messagingTimeout: Float = 1

    /// Dismisses every notification currently on screen — banners, and stacks
    /// in the open Notification Center. Does nothing without Accessibility
    /// permission or when there are no notifications.
    static func dismissAll() {
        guard let (tree, windows) = liveTree() else { return }
        let dismissed = NotificationDismissal.dismissAll(in: tree, roots: windows, names: dismissNames)
        log.info("dismissed \(dismissed) notification(s)")
    }

    #if DEBUG
    /// What `dismissAll` would press right now, without pressing it: one
    /// `subrole → action` line per target. For checking the live walk against
    /// real notifications (which a test shouldn't clear).
    static func describeTargets() -> [String] {
        guard let (tree, windows) = liveTree() else { return ["ERROR: Notification Center unreachable"] }
        return NotificationDismissal.targets(in: tree, roots: windows, names: dismissNames).map {
            "\(tree.subrole(of: $0.element) ?? "?") → \(NotificationDismissal.displayName(of: $0.action) ?? "?")"
        }
    }
    #endif

    private static func liveTree() -> (tree: LiveNotificationTree, windows: [AXUIElement])? {
        guard Paster.isTrusted else {
            log.info("dismiss notifications: Accessibility not granted")
            return nil
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        }) else {
            log.info("dismiss notifications: Notification Center not running")
            return nil
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, messagingTimeout)
        // Windows only: the app element's children also include its menu bar,
        // whose Apple menu is hundreds of items with nothing to dismiss.
        return (LiveNotificationTree(), LiveNotificationTree.windows(of: axApp))
    }
}

/// The live accessibility tree. Not isolated: the AX calls are plain C, and
/// keeping the conformance free of an actor lets tests and callers use it anywhere.
private struct LiveNotificationTree: NotificationTree {
    func children(of element: AXUIElement) -> [AXUIElement] {
        Self.elements(of: element, attribute: kAXChildrenAttribute)
    }

    static func windows(of app: AXUIElement) -> [AXUIElement] {
        elements(of: app, attribute: kAXWindowsAttribute)
    }

    private static func elements(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AnyObject] else { return [] }
        return array.compactMap {
            guard CFGetTypeID($0) == AXUIElementGetTypeID() else { return nil }
            return ($0 as! AXUIElement) // swiftlint:disable:this force_cast
        }
    }

    func subrole(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    func perform(_ action: String, on element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }
}
