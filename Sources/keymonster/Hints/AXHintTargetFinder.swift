import AppKit
import ApplicationServices
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints.finder")

/// Walks the accessibility tree of the frontmost app's focused window and
/// returns every on-screen clickable element, so hint mode can label them.
@MainActor
enum AXHintTargetFinder {
    struct Scan {
        let targets: [HintTarget]
        /// Focused window frame in AX (global, top-left origin) coordinates.
        let windowFrame: CGRect
    }

    /// Traversal bounds so a huge web page can't hang the app: breadth-first,
    /// capped by element count and wall-clock time. Elements beyond the cap
    /// simply don't get hints.
    private static let maxElements = 3000
    private static let timeBudget: TimeInterval = 0.5
    /// How long to keep retrying a web-backed app whose content tree hasn't
    /// materialized yet (see `scan`). A fallback for activating hint mode before
    /// `AXPrewarmer` has finished; bounded so a native-only window in a web app,
    /// or a blank page, can't stall activation.
    private static let tenacityBudget: TimeInterval = 1.0

    /// One breadth-first pass over the window; `foundWebContent` reports whether
    /// a populated `AXWebArea` was seen, which tells `scan` the web tree has been
    /// built (as opposed to only the native chrome).
    struct Walk {
        var targets: [HintTarget]
        var foundWebContent: Bool
    }

    static func scan() -> Scan? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        // Browsers and Electron apps only build an accessibility tree for their
        // web content once an assistive client asks for it. These app-level
        // attributes are that ask: WebKit/AppKit honor the first, Chromium and
        // Electron the second. (Chromium returns an error from the set yet still
        // acts on it, so the return value is not a usable signal — we classify
        // the app by its bundle instead. `AXPrewarmer` normally makes this ask on
        // app switch, so the tree is usually already built by now.)
        AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let webBacked = WebApp.isWebBacked(app)

        guard let window = focusedWindow(of: axApp), let windowFrame = frame(of: window) else {
            log.info("no focused window for \(app.bundleIdentifier ?? "?")")
            return nil
        }

        // The first pass on a freshly-enabled Chromium/Electron window often sees
        // only the native chrome (toolbar, traffic lights) because the AXWebArea
        // hasn't been built yet. Re-walk until the web content shows up, bounded
        // so a native window or an empty page can't stall activation.
        let deadline = Date().addingTimeInterval(tenacityBudget)
        var result = walk(window: window, windowFrame: windowFrame)
        var attempts = 1
        while webBacked, !result.foundWebContent, Date() < deadline {
            usleep(50_000)
            result = walk(window: window, windowFrame: windowFrame)
            attempts += 1
        }

        // The walk only dedupes pixel-identical frames; this folds nested
        // wrappers and near-coincident frames that are really one click.
        let coalesced = HintTargetFilter.coalesced(result.targets)
        log.debug("""
            scan: \(result.targets.count) targets (\(coalesced.count) coalesced) in \
            \(attempts) walk(s), webBacked=\(webBacked), webContent=\(result.foundWebContent)
            """)
        return Scan(targets: coalesced, windowFrame: windowFrame)
    }

    /// A single breadth-first sweep of `window` for clickable, on-screen targets.
    /// Internal so the `hintscan` debug runner can measure a lone pass.
    static func walk(window: AXUIElement, windowFrame: CGRect) -> Walk {
        let start = Date()
        var targets: [HintTarget] = []
        var seenFrames: Set<String> = []
        var queue: [AXUIElement] = [window]
        var head = 0
        var foundWebContent = false

        while head < queue.count, head < maxElements, Date().timeIntervalSince(start) < timeBudget {
            let element = queue[head]
            head += 1

            let values = attributes(of: element, [
                kAXRoleAttribute as String,
                kAXPositionAttribute as String,
                kAXSizeAttribute as String,
                kAXChildrenAttribute as String
            ])
            let role = values[0] as? String
            let elementFrame = frame(position: values[1], size: values[2])
            let childElements = children(from: values[3])

            // A web area with children means Chromium/WebKit has built the
            // content subtree — the signal `scan` waits for.
            if role == "AXWebArea", !childElements.isEmpty {
                foundWebContent = true
            }

            if let elementFrame,
               HintTargetFilter.isVisible(frame: elementFrame, within: windowFrame),
               isClickable(element, role: role) {
                let visible = elementFrame.intersection(windowFrame)
                let key = "\(Int(visible.minX)),\(Int(visible.minY)),\(Int(visible.width)),\(Int(visible.height))"
                if seenFrames.insert(key).inserted {
                    targets.append(HintTarget(frame: visible, role: role))
                }
            }

            // Skip subtrees that are provably outside the window (scrolled-away
            // content); recurse into everything else, including elements that
            // don't report a frame at all.
            if let elementFrame, !elementFrame.isEmpty, !elementFrame.intersects(windowFrame) {
                continue
            }
            queue.append(contentsOf: childElements)
        }
        return Walk(targets: targets, foundWebContent: foundWebContent)
    }

    /// The frontmost app's focused window frame in AX coordinates, for overlays
    /// that don't need an element scan (grid mode).
    static func focusedWindowFrame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = focusedWindow(of: axApp) else {
            log.info("no focused window for \(app.bundleIdentifier ?? "?")")
            return nil
        }
        return frame(of: window)
    }

    // MARK: - AX plumbing
    // Internal (not private) so AXScrollPaneFinder can walk the same tree
    // without duplicating the plumbing.

    static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        if let focused = element(of: app, attribute: kAXFocusedWindowAttribute) {
            return focused
        }
        // No focused window (e.g. only a hovered panel): fall back to the first.
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else {
            return nil
        }
        return children(from: value).first
    }

    static func element(of parent: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement) // swiftlint:disable:this force_cast

    }

    static func frame(of element: AXUIElement) -> CGRect? {
        let values = attributes(of: element, [kAXPositionAttribute as String, kAXSizeAttribute as String])
        return frame(position: values[0], size: values[1])
    }

    /// Fetches several attributes in one IPC round trip. Failed attributes come
    /// back as nil entries; a failed call comes back as all-nil.
    static func attributes(of element: AXUIElement, _ names: [String]) -> [Any?] {
        var values: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element, names as CFArray, AXCopyMultipleAttributeOptions(), &values
        )
        guard error == .success, let array = values as? [AnyObject], array.count == names.count else {
            return [Any?](repeating: nil, count: names.count)
        }
        return array.map { value -> Any? in
            if value is NSNull { return nil }
            if CFGetTypeID(value) == AXValueGetTypeID(),
               AXValueGetType(value as! AXValue) == .axError { // swiftlint:disable:this force_cast
                return nil
            }
            return value
        }
    }

    static func frame(position: Any?, size: Any?) -> CGRect? {
        guard let position = position as AnyObject?, let size = size as AnyObject?,
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        // swiftlint:disable force_cast
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else {
            return nil
        }
        // swiftlint:enable force_cast
        return CGRect(origin: point, size: dimensions)
    }

    static func children(from value: Any?) -> [AXUIElement] {
        guard let array = value as? [AnyObject] else { return [] }
        return array.compactMap {
            guard CFGetTypeID($0) == AXUIElementGetTypeID() else { return nil }
            return ($0 as! AXUIElement) // swiftlint:disable:this force_cast
        }
    }

    private static func isClickable(_ element: AXUIElement, role: String?) -> Bool {
        if let role, HintTargetFilter.clickableRoles.contains(role) { return true }
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let actions = names as? [String] else {
            return false
        }
        return HintTargetFilter.isClickable(role: role, actions: actions)
    }
}
