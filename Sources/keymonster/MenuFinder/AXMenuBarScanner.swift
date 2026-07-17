import AppKit
import ApplicationServices
import os.log

private let log = Logger(subsystem: "keymonster", category: "menufinder.scanner")

/// Reads an app's menu bar through the accessibility API and returns every
/// enabled, actionable leaf item, plus the `AXUIElement` to press for each. The
/// structure is the one AppKit builds for a standard `NSMenu`: the menu bar's
/// children are the top-level menus, each holds an `AXMenu`, and that menu's
/// children are `AXMenuItem`s — items with their own submenu recurse, leaves are
/// collected. Reading attributes never opens a menu on screen (only pressing
/// does), so scanning is invisible.
@MainActor
enum AXMenuBarScanner {
    struct Scan {
        let items: [MenuBarItem]
        /// The pressable element for each item, keyed by `MenuBarItem.id`.
        let elements: [Int: AXUIElement]
        let appName: String
    }

    /// Bounds so a pathological menu can't hang the app: recursion depth, total
    /// item count, and wall-clock. Items beyond a cap simply don't appear.
    private static let maxDepth = 8
    private static let maxItems = 2000
    private static let timeBudget: TimeInterval = 1.0

    static func scan(app: NSRunningApplication) -> Scan? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let menuBar = element(of: axApp, attribute: kAXMenuBarAttribute) else {
            log.info("no menu bar for \(app.bundleIdentifier ?? "?")")
            return nil
        }

        var collector = Collector(deadline: Date().addingTimeInterval(timeBudget))
        // Skip the first top-level menu: it's the system Apple menu, whose items
        // (About This Mac, Sleep, …) belong to macOS, not the active app.
        for topMenu in children(of: menuBar).dropFirst() {
            let title = string(of: topMenu, attribute: kAXTitleAttribute) ?? ""
            collector.walk(container: topMenu, path: title.isEmpty ? [] : [title], depth: 1)
        }

        log.debug("scanned \(collector.items.count) menu item(s) for \(app.bundleIdentifier ?? "?")")
        return Scan(
            items: collector.items,
            elements: collector.elements,
            appName: app.localizedName ?? title(of: menuBar) ?? ""
        )
    }

    /// Trigger a menu item by synthesizing its press action.
    static func press(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    // MARK: - Traversal

    /// Accumulates leaves depth-first while enforcing the scan bounds.
    @MainActor
    private struct Collector {
        let deadline: Date
        var items: [MenuBarItem] = []
        var elements: [Int: AXUIElement] = [:]
        private var nextID = 0

        init(deadline: Date) { self.deadline = deadline }

        mutating func walk(container: AXUIElement, path: [String], depth: Int) {
            guard depth <= maxDepth, items.count < maxItems, Date() < deadline else { return }
            guard let menu = submenu(of: container) else { return }

            for item in children(of: menu) {
                guard items.count < maxItems, Date() < deadline else { return }
                let title = (string(of: item, attribute: kAXTitleAttribute) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if submenu(of: item) != nil {
                    // A container: descend, extending the breadcrumb by its label.
                    walk(container: item, path: title.isEmpty ? path : path + [title], depth: depth + 1)
                } else if !title.isEmpty, isEnabled(item) {
                    // An actionable leaf. Disabled items and separators (no title)
                    // are skipped — there's nothing to run.
                    items.append(MenuBarItem(id: nextID, path: path, title: title))
                    elements[nextID] = item
                    nextID += 1
                }
            }
        }
    }

    // MARK: - AX plumbing

    private static func submenu(of element: AXUIElement) -> AXUIElement? {
        children(of: element).first { string(of: $0, attribute: kAXRoleAttribute) == kAXMenuRole }
    }

    private static func title(of menuBar: AXUIElement) -> String? {
        string(of: menuBar, attribute: kAXTitleAttribute)
    }

    private static func element(of parent: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement) // swiftlint:disable:this force_cast
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AnyObject] else {
            return []
        }
        return array.compactMap {
            guard CFGetTypeID($0) == AXUIElementGetTypeID() else { return nil }
            return ($0 as! AXUIElement) // swiftlint:disable:this force_cast
        }
    }

    private static func string(of element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    /// Whether a menu item is actionable. Only an explicit `false` disables it;
    /// a missing or unreadable attribute is treated as enabled, so a quirk in one
    /// app can't silently blank the whole list.
    private static func isEnabled(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value) == .success else {
            return true
        }
        return (value as? Bool) ?? true
    }
}
