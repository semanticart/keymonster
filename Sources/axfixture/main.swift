import AppKit
import WebKit

/// A window of text fields covering every accessibility shape text jump has to
/// cope with, so the modes can be exercised against real AX servers without
/// needing Slack or Chrome installed.
///
/// Development tooling: a separate executable target, never linked into the app.
/// `make fixture` launches it to poke at by hand; `make axtest` drives it from
/// `AXLiveTreeTests`, which reads this window's real accessibility tree.
///
/// Each field's text is distinctive so the test can find it by value without
/// having to move focus around.
enum Fixture {
    static let nativeFieldText = "fixture native field hello"
    static let nativeTextViewText = "fixture text view hello over two lines"
    static let searchFieldText = "fixture search hello"
    static let omniboxText = "https://fixture.example.com/path?query=hello"
    static let webInputText = "fixture web input hello"
    static let webEditableText = "fixture web editable hello"
}

/// Mimics Chrome's omnibox: reports a role, a value, and a settable selection,
/// but implements no per-character geometry and vends no children. That
/// combination is what defeats text jump, and recreating it here means the gap
/// can be reproduced without Chrome. The *absence* of `accessibilityFrame(for:)`
/// below is the entire point — don't add it.
final class OmniboxMimicView: NSView {
    private var selection = NSRange(location: 0, length: 0)

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setStroke()
        bounds.insetBy(dx: 0.5, dy: 0.5).frame()
        (Fixture.omniboxText as NSString).draw(
            at: NSPoint(x: 5, y: 4),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    override func isAccessibilityElement() -> Bool { true }
    override func isAccessibilityEnabled() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textField }
    override func accessibilityValue() -> Any? { Fixture.omniboxText }
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityNumberOfCharacters() -> Int { Fixture.omniboxText.utf16.count }
    override func accessibilitySelectedTextRange() -> NSRange { selection }
    override func setAccessibilitySelectedTextRange(_ range: NSRange) { selection = range }

    /// Only the selection setter is writable, so `AXSelectedTextRange` reports
    /// settable — the check text jump uses to decide a field is editable.
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        selector == #selector(setAccessibilitySelectedTextRange(_:))
            || super.isAccessibilitySelectorAllowed(selector)
    }
}

final class FixtureDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.title = "Key Monster AX Fixture"
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Native AppKit: bounds come off the field itself, caret moves by offset.
        stack.addArrangedSubview(label("NSTextField — native, AXBoundsForRange on the field"))
        stack.addArrangedSubview(field(Fixture.nativeFieldText))

        stack.addArrangedSubview(label("NSTextView — native, multi-line"))
        stack.addArrangedSubview(textView(Fixture.nativeTextViewText))

        stack.addArrangedSubview(label("NSSearchField — native, subrole AXSearchField"))
        stack.addArrangedSubview(searchField(Fixture.searchFieldText))

        stack.addArrangedSubview(label("Omnibox mimic — no geometry, no children (the Chrome shape)"))
        let omnibox = OmniboxMimicView()
        omnibox.translatesAutoresizingMaskIntoConstraints = false
        omnibox.heightAnchor.constraint(equalToConstant: 24).isActive = true
        omnibox.widthAnchor.constraint(equalToConstant: 560).isActive = true
        stack.addArrangedSubview(omnibox)

        stack.addArrangedSubview(label("WKWebView — web, geometry on nested AXStaticText leaves"))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 150))
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.heightAnchor.constraint(equalToConstant: 150).isActive = true
        webView.widthAnchor.constraint(equalToConstant: 560).isActive = true
        stack.addArrangedSubview(webView)

        window.contentView = stack
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.loadHTMLString(
            """
            <html><body style="font: 15px -apple-system; margin: 10px">
            <input id="i" style="width: 90%; font-size: 15px" value="\(Fixture.webInputText)">
            <div id="e" contenteditable="true" style="border: 1px solid #999; padding: 6px; margin-top: 8px">
            \(Fixture.webEditableText)
            </div>
            </body></html>
            """,
            baseURL: nil
        )
    }

    /// The test waits on this line before reading the tree, so the web content
    /// is guaranteed to be laid out and vending accessibility by then.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("fixture ready")
        fflush(stdout)
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func field(_ text: String) -> NSTextField {
        let field = NSTextField(string: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 560).isActive = true
        return field
    }

    private func searchField(_ text: String) -> NSSearchField {
        let field = NSSearchField()
        field.stringValue = text
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 560).isActive = true
        return field
    }

    private func textView(_ text: String) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        (scroll.documentView as? NSTextView)?.string = text
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 60).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 560).isActive = true
        return scroll
    }
}

let app = NSApplication.shared
let delegate = FixtureDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
