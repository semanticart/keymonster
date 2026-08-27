#if DEBUG
import AppKit
import ApplicationServices

/// `keymonster hintscan <bundle-id-substring> <output-path> [both|manual|enhanced|none]`
/// — activates the matching app and traces successive hint-target walks of its
/// focused window, writing per pass how many clickable targets were found and
/// whether the web content tree has materialized. Makes the Chromium/Electron
/// cold-start race visible: the first pass on a freshly-launched web app finds
/// only the native chrome (`webContent=false`), then the content fills in a few
/// passes later. The optional last argument picks which AX enable attributes to
/// set (default `both`), so each one's effect can be measured in isolation;
/// `none` is the control for whether walking alone triggers the build.
///
/// Run via `open -n --args …` so it uses the app's own Accessibility grant; the
/// output goes to a file because a detached launch's stdout is lost.
@MainActor
enum HintScanRunner {
    static func main() {
        guard let flagIndex = CommandLine.arguments.firstIndex(of: "hintscan"),
              CommandLine.arguments.count >= flagIndex + 3 else {
            fputs("usage: keymonster hintscan <bundle-id-substring> <output-path>\n", stderr)
            exit(2)
        }
        let query = CommandLine.arguments[flagIndex + 1].lowercased()
        let outputPath = CommandLine.arguments[flagIndex + 2]
        let attrsMode = CommandLine.arguments.count > flagIndex + 3
            ? CommandLine.arguments[flagIndex + 3] : "both"
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

        app.activate()
        usleep(800_000)

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        if attrsMode == "both" || attrsMode == "enhanced" {
            AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        if attrsMode == "both" || attrsMode == "manual" {
            AXUIElementSetAttributeValue(axApp, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }

        guard let window = AXHintTargetFinder.focusedWindow(of: axApp),
              let windowFrame = AXHintTargetFinder.frame(of: window) else {
            out += "ERROR: no focused window for \(app.bundleIdentifier ?? "?")\n"
            return
        }

        out += "app: \(app.bundleIdentifier ?? "?")  webBacked=\(WebApp.isWebBacked(app))  attrs=\(attrsMode)\n"
        let start = Date()
        var attempt = 0
        while Date().timeIntervalSince(start) < 4.0 {
            attempt += 1
            let walk = AXHintTargetFinder.walk(window: window, windowFrame: windowFrame)
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            out += "pass \(attempt) @\(elapsedMs)ms: targets=\(walk.targets.count) webContent=\(walk.foundWebContent)\n"
            if walk.foundWebContent { break }
            usleep(50_000)
        }
    }
}
#endif
