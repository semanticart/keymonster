#if DEBUG
import AppKit
import ApplicationServices

/// `keymonster axdump <bundle-id-substring> <output-path>` — dumps another
/// app's focused-window accessibility tree to a file, one indented line per
/// element with its role, frame, and any scroll-related attributes. Debug-only
/// development tooling for chasing how a given app (Electron especially)
/// models its scrollable panes.
///
/// Run it via `open -n --args …`, not from a shell: a terminal-spawned process
/// inherits the terminal's Accessibility (non-)grant, while a launchd-launched
/// copy uses the app's own — the same reason `make axtest` needs the terminal
/// itself trusted.
@MainActor
enum AXDumpRunner {
    private static let maxElements = 20000
    private static let timeBudget: TimeInterval = 10

    static func main() {
        guard let flagIndex = CommandLine.arguments.firstIndex(of: "axdump"),
              CommandLine.arguments.count >= flagIndex + 3 else {
            fputs("usage: keymonster axdump <bundle-id-substring> <output-path>\n", stderr)
            exit(2)
        }
        let query = CommandLine.arguments[flagIndex + 1].lowercased()
        let outputPath = CommandLine.arguments[flagIndex + 2]
        var out = ""

        defer {
            try? out.write(toFile: outputPath, atomically: true, encoding: .utf8)
            exit(0)
        }

        guard AXIsProcessTrusted() else {
            out = "ERROR: not trusted for Accessibility\n"
            return
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier?.lowercased().contains(query) == true
        }) else {
            out = "ERROR: no running app whose bundle id contains \(query)\n"
            return
        }
        out += "app: \(app.bundleIdentifier ?? "?") pid \(app.processIdentifier)\n"

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        guard let window = AXHintTargetFinder.focusedWindow(of: axApp) else {
            out += "ERROR: no window\n"
            return
        }
        out += dump(window)
    }

    private static func dump(_ window: AXUIElement) -> String {
        var out = ""
        let start = Date()
        var histogram: [String: Int] = [:]
        var count = 0
        var stack: [(element: AXUIElement, depth: Int)] = [(window, 0)]

        while let (element, depth) = stack.popLast(),
              count < maxElements, Date().timeIntervalSince(start) < timeBudget {
            count += 1
            let values = AXHintTargetFinder.attributes(of: element, [
                kAXRoleAttribute as String,
                kAXSubroleAttribute as String,
                kAXPositionAttribute as String,
                kAXSizeAttribute as String,
                kAXChildrenAttribute as String
            ])
            let role = values[0] as? String ?? "?"
            histogram[role, default: 0] += 1
            let subrole = (values[1] as? String).map { "/\($0)" } ?? ""
            let frame = AXHintTargetFinder.frame(position: values[2], size: values[3])
            let frameText = frame.map {
                "(\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height)))"
            } ?? "(no frame)"
            let children = AXHintTargetFinder.children(from: values[4])

            var names: CFArray?
            var scrollish = ""
            if AXUIElementCopyAttributeNames(element, &names) == .success,
               let all = names as? [String] {
                let hits = all.filter { $0.localizedCaseInsensitiveContains("scroll") }
                if !hits.isEmpty { scrollish = " attrs:[\(hits.joined(separator: ","))]" }
            }
            if role == kAXScrollBarRole as String {
                let state = AXHintTargetFinder.attributes(of: element, [
                    kAXEnabledAttribute as String,
                    kAXValueAttribute as String,
                    kAXOrientationAttribute as String
                ])
                scrollish += " enabled:\(state[0] ?? "?") value:\(state[1] ?? "?")"
                    + " orientation:\(state[2] ?? "?")"
            }

            out += String(repeating: "  ", count: depth)
                + "\(role)\(subrole) \(frameText)\(scrollish) kids:\(children.count)\n"
            for child in children.reversed() {
                stack.append((child, depth + 1))
            }
        }

        out += "\n\(count) elements in \(-start.timeIntervalSinceNow)s\nroles:\n"
        for (role, tally) in histogram.sorted(by: { $0.value > $1.value }) {
            out += "  \(tally)\t\(role)\n"
        }
        return out
    }
}

/// `keymonster scrollscan <bundle-id-substring> <output-path>` — runs the real
/// `AXScrollPaneFinder.scan` against a named app and writes the panes it
/// found, so pane detection can be checked against e.g. Slack without
/// foregrounding it and pressing the hotkey by hand. Launch via `open -n
/// --args …` for the same Accessibility reason as `axdump`.
@MainActor
enum ScrollScanRunner {
    static func main() {
        guard let flagIndex = CommandLine.arguments.firstIndex(of: "scrollscan"),
              CommandLine.arguments.count >= flagIndex + 3 else {
            fputs("usage: keymonster scrollscan <bundle-id-substring> <output-path>\n", stderr)
            exit(2)
        }
        let query = CommandLine.arguments[flagIndex + 1].lowercased()
        let outputPath = CommandLine.arguments[flagIndex + 2]
        var out = ""

        defer {
            try? out.write(toFile: outputPath, atomically: true, encoding: .utf8)
            exit(0)
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier?.lowercased().contains(query) == true
        }) else {
            out = "ERROR: no running app whose bundle id contains \(query)\n"
            return
        }
        guard let scan = AXScrollPaneFinder.scan(of: app) else {
            out = "ERROR: scan failed (no window, or not trusted)\n"
            return
        }
        out += "window: \(scan.windowFrame)\n\(scan.panes.count) pane(s):\n"
        for pane in scan.panes {
            out += "  \(pane.frame)\n"
        }
    }
}

/// `keymonster scrolltest <bundle-id-substring> <output-path>` — foregrounds a
/// named app, aims `ScrollWheel.scroll` (the exact call scroll mode makes) at
/// its biggest pane, and reports whether an element inside actually moved.
/// Scrolls back and puts the cursor back when done, so the app is left as it
/// was. Launch via `open -n --args …` like the others.
@MainActor
enum ScrollTestRunner {
    static func main() {
        guard let flagIndex = CommandLine.arguments.firstIndex(of: "scrolltest"),
              CommandLine.arguments.count >= flagIndex + 3 else {
            fputs("usage: keymonster scrolltest <bundle-id-substring> <output-path>\n", stderr)
            exit(2)
        }
        let query = CommandLine.arguments[flagIndex + 1].lowercased()
        let outputPath = CommandLine.arguments[flagIndex + 2]
        let out = run(query: query)
        try? out.write(toFile: outputPath, atomically: true, encoding: .utf8)
        exit(0)
    }

    private static func run(query: String) -> String {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier?.lowercased().contains(query) == true
        }) else {
            return "ERROR: no running app whose bundle id contains \(query)\n"
        }
        // The scroll only lands if the pane is actually under the pointer on
        // screen, so the app must be frontmost while the events post.
        app.activate()
        usleep(800_000)
        guard let scan = AXScrollPaneFinder.scan(of: app),
              let pane = scan.panes.max(by: { area(of: $0, in: scan) < area(of: $1, in: scan) })
        else {
            return "ERROR: scan failed or no panes\n"
        }
        let rect = pane.frame.intersection(scan.windowFrame)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        guard let marker = marker(in: pane.element, around: rect),
              let before = AXHintTargetFinder.frame(of: marker) else {
            return "ERROR: no trackable element inside the pane\n"
        }

        let cursor = CGEvent(source: nil)?.location
        var out = "pane: \(rect)\nmarker: \(before)\n"

        // Ground truth is screen pixels around the scroll point: AX frames in
        // Chromium can lag, and each event variant needs its own verdict. The
        // cursor parks on the center first so hover styling is identical in
        // both captures.
        CGWarpMouseCursorPosition(center)
        usleep(300_000)
        for variant in variants {
            let frameBefore = capture(around: center)
            variant.post(-180, center)
            usleep(500_000)
            let frameAfter = capture(around: center)
            variant.post(180, center) // put the pane back
            usleep(500_000)
            out += "\(variant.name): \(diff(frameBefore, frameAfter))\n"
        }
        if let cursor { CGWarpMouseCursorPosition(cursor) }
        return out
    }

    private struct Variant {
        let name: String
        let post: (Int32, CGPoint) -> Void
    }

    private static let variants: [Variant] = [
        Variant(name: "line-units (control)") { amount, point in
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                wheel1: amount / 30, wheel2: 0, wheel3: 0
            ) else { return }
            event.location = point
            event.post(tap: .cghidEventTap)
        },
        Variant(name: "pixel-units") { amount, point in
            MainActor.assumeIsolated { ScrollWheel.scroll(pixels: amount, at: point) }
        },
        Variant(name: "pixel-units-with-phases") { amount, point in
            // A trackpad gesture: began, one changed carrying the distance,
            // ended. Chromium is said to gate continuous scrolls on phases.
            for (phase, delta): (Int64, Int32) in [(1, 0), (2, amount), (4, 0)] {
                guard let event = CGEvent(
                    scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                    wheel1: delta, wheel2: 0, wheel3: 0
                ) else { continue }
                event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
                event.location = point
                event.post(tap: .cghidEventTap)
            }
        }
    ]

    private static func capture(around point: CGPoint) -> Data? {
        let rect = CGRect(x: point.x - 150, y: point.y - 80, width: 300, height: 160)
        guard let image = CGWindowListCreateImage(
            rect, .optionOnScreenOnly, kCGNullWindowID, [.boundsIgnoreFraming]
        ) else { return nil }
        return image.dataProvider?.data as Data?
    }

    private static func diff(_ before: Data?, _ after: Data?) -> String {
        guard let before, let after else { return "capture failed (Screen Recording?)" }
        guard before.count == after.count else { return "scrolled (sizes differ)" }
        let differing = zip(before, after).lazy.filter { $0 != $1 }.count
        let fraction = Double(differing) / Double(before.count)
        let percent = Int(fraction * 100)
        return fraction > 0.02 ? "SCROLLED (\(percent)% of pixels moved)" : "did not scroll"
    }

    private static func area(of pane: ScrollPane, in scan: AXScrollPaneFinder.Scan) -> CGFloat {
        let rect = pane.frame.intersection(scan.windowFrame)
        return rect.isEmpty ? 0 : rect.width * rect.height
    }

    /// A smallish element in the pane's vertical middle, whose frame will
    /// shift if the pane's content scrolls.
    private static func marker(in root: AXUIElement, around rect: CGRect) -> AXUIElement? {
        var queue = [root]
        var head = 0
        while head < queue.count, head < 2000 {
            let element = queue[head]
            head += 1
            // Near the pane's center on both axes — that's where the wheel
            // event lands, and a sidebar element wouldn't move with it.
            if let frame = AXHintTargetFinder.frame(of: element),
               frame.height > 4, frame.height < 120,
               abs(frame.midY - rect.midY) < rect.height / 4,
               abs(frame.midX - rect.midX) < rect.width / 4 {
                return element
            }
            let values = AXHintTargetFinder.attributes(of: element, [kAXChildrenAttribute as String])
            queue.append(contentsOf: AXHintTargetFinder.children(from: values[0]))
        }
        return nil
    }
}
#endif
