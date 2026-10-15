import XCTest
@testable import keymonster

/// Link finding over screen text as kitty's `get-text --ansi` returns it. The
/// inputs are shaped like captures from kitty, bare and inside tmux.
final class TerminalLinksTests: XCTestCase {
    private let esc = "\u{1b}"

    private func osc8(_ url: String, _ label: String, params: String = "") -> String {
        "\(esc)]8;\(params);\(url)\(esc)\\\(label)\(esc)]8;;\(esc)\\"
    }

    func testBareURLIsLocatedOnItsRow() {
        let text = "\(esc)[mfirst line\n\(esc)[mplain: https://example.com/a?x=1\n"
        let links = TerminalLinks.find(inANSI: text, columns: 80)
        XCTAssertEqual(links, [
            TerminalLink(url: "https://example.com/a?x=1", spans: [CellSpan(row: 1, startColumn: 7, endColumn: 32)])
        ])
    }

    func testHyperlinkYieldsItsTargetAndLabelCells() {
        let text = "linked: " + osc8("https://example.com/linked", "Docs link text", params: "id=tmux1") + " after"
        XCTAssertEqual(TerminalLinks.find(inANSI: text, columns: 80), [
            TerminalLink(
                url: "https://example.com/linked",
                spans: [CellSpan(row: 0, startColumn: 8, endColumn: 22)]
            )
        ])
    }

    func testURLWrappedByTheTerminalIsOneLinkWithASpanPerRow() {
        // tmux drops a bare SGR reset right at its wrap boundary, mid-URL.
        let head = "long: https://example.com/" + String(repeating: "a", count: 54)
        let tail = String(repeating: "a", count: 66) + " end"
        let text = "\(esc)[m" + head + "\(esc)[m" + tail + "\n"
        let links = TerminalLinks.find(inANSI: text, columns: 80)

        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].url, "https://example.com/" + String(repeating: "a", count: 120))
        XCTAssertEqual(links[0].spans, [
            CellSpan(row: 0, startColumn: 6, endColumn: 80),
            CellSpan(row: 1, startColumn: 0, endColumn: 66)
        ])
    }

    func testHyperlinkLabelThatWrapsKeepsItsFullTarget() {
        let text = String(repeating: "p", count: 70)
            + osc8("https://example.com/wrapped-link", "Linked label that wraps") + " tail"
        let links = TerminalLinks.find(inANSI: text, columns: 80)

        XCTAssertEqual(links.map(\.url), ["https://example.com/wrapped-link"])
        XCTAssertEqual(links[0].spans, [
            CellSpan(row: 0, startColumn: 70, endColumn: 80),
            CellSpan(row: 1, startColumn: 0, endColumn: 13)
        ])
    }

    func testBareURLDoesNotRunAcrossAHardLineBreak() {
        let text = "see https://example.com/a\nb is not part of it\n"
        XCTAssertEqual(TerminalLinks.find(inANSI: text, columns: 80).map(\.url), ["https://example.com/a"])
    }

    func testURLInsideAHyperlinkLabelIsNotFoundTwice() {
        let text = osc8("https://example.com/real", "https://example.com/shown")
        XCTAssertEqual(TerminalLinks.find(inANSI: text, columns: 80).map(\.url), ["https://example.com/real"])
    }

    func testTrailingSentencePunctuationIsNotPartOfTheURL() {
        let text = "Visit https://example.com/page, or https://example.org/x. Then (https://example.net/y) and "
            + "https://en.wikipedia.org/wiki/Foo_(bar)!"
        XCTAssertEqual(TerminalLinks.find(inANSI: text, columns: 200).map(\.url), [
            "https://example.com/page", "https://example.org/x",
            "https://example.net/y", "https://en.wikipedia.org/wiki/Foo_(bar)"
        ])
    }

    func testBoxDrawingBordersEndAURL() {
        let text = "│ https://example.com/boxed │\n"
        let links = TerminalLinks.find(inANSI: text, columns: 80)
        XCTAssertEqual(links.map(\.url), ["https://example.com/boxed"])
        XCTAssertEqual(links[0].spans, [CellSpan(row: 0, startColumn: 2, endColumn: 27)])
    }

    func testWideCharactersTakeTwoCells() {
        let text = "日本 https://example.com/w 🎉 https://example.com/z"
        let links = TerminalLinks.find(inANSI: text, columns: 80)
        XCTAssertEqual(links[0].spans, [CellSpan(row: 0, startColumn: 5, endColumn: 26)])
        // 5 + 21 URL cells + space = 27, emoji 2 cells, space → 30.
        XCTAssertEqual(links[1].spans.first?.startColumn, 30)
    }

    func testOtherEscapesAreSkipped() {
        let text = "\(esc)[1;38;2;1;2;3mred\(esc)[0m \(esc)]0;window title\u{07}https://example.com/t"
        XCTAssertEqual(TerminalLinks.find(inANSI: text, columns: 80).map(\.url), ["https://example.com/t"])
    }

    func testNoLinksAndNoColumns() {
        XCTAssertEqual(TerminalLinks.find(inANSI: "nothing here\n", columns: 80), [])
        XCTAssertEqual(TerminalLinks.find(inANSI: "https://example.com", columns: 0), [])
    }

    // MARK: - Grid

    func testGridMapsSpansToRects() {
        let grid = TerminalGrid(frame: CGRect(x: 100, y: 50, width: 800, height: 480), columns: 80, lines: 24)
        let rect = grid.rect(for: CellSpan(row: 2, startColumn: 10, endColumn: 30))
        XCTAssertEqual(rect, CGRect(x: 200, y: 90, width: 200, height: 20))
    }

    func testGridTargetsOpenTheLinkAndLabelItsFirstRow() {
        let grid = TerminalGrid(frame: CGRect(x: 0, y: 0, width: 800, height: 480), columns: 80, lines: 24)
        let link = TerminalLink(url: "https://example.com/u", spans: [
            CellSpan(row: 1, startColumn: 70, endColumn: 80), CellSpan(row: 2, startColumn: 0, endColumn: 13)
        ])
        let expected = HintTarget(
            frame: CGRect(x: 700, y: 20, width: 100, height: 20), role: "AXLink",
            linkURL: "https://example.com/u"
        )
        XCTAssertEqual(grid.targets(for: [link]), [expected])
    }

    func testGridDropsLinksBelowTheVisibleLines() {
        let grid = TerminalGrid(frame: CGRect(x: 0, y: 0, width: 800, height: 480), columns: 80, lines: 24)
        let link = TerminalLink(url: "u", spans: [CellSpan(row: 24, startColumn: 0, endColumn: 5)])
        XCTAssertEqual(grid.targets(for: [link]), [])
    }
}

/// Reading kitty's window size and screen text through an injected `kitten @`.
final class KittyRemoteTests: XCTestCase {
    private func listing(osFocused: Bool = true, tabActive: Bool = true, windows: Int = 1) -> Data {
        let window = #"{"id": 1, "is_focused": true, "columns": 193, "lines": 65}"#
        let tab = """
            {"is_active": \(tabActive), "windows": [\(Array(repeating: window, count: windows).joined(separator: ","))]}
            """
        return Data(#"[{"is_focused": \#(osFocused), "tabs": [\#(tab)]}]"#.utf8)
    }

    func testFocusedWindowSize() {
        let size = KittyRemote.focusedWindowSize(inLS: listing())
        XCTAssertEqual(size?.columns, 193)
        XCTAssertEqual(size?.lines, 65)
    }

    func testFocusedWindowInfoCarriesTheForegroundPIDs() {
        let window = #"""
            {"is_focused": true, "columns": 10, "lines": 5,
             "foreground_processes": [{"pid": 4242, "cmdline": ["tmux", "attach"]}, {"pid": 7}]}
            """#
        let data = Data(#"[{"is_focused": true, "tabs": [{"is_active": true, "windows": [\#(window)]}]}]"#.utf8)
        XCTAssertEqual(KittyRemote.focusedWindowInfo(inLS: data)?.foregroundPIDs, [4242, 7])
    }

    func testFocusedWindowInfoCarriesTheWorkingDirectory() {
        let window = #"{"is_focused": true, "columns": 10, "lines": 5, "cwd": "/Users/me/proj"}"#
        let data = Data(#"[{"is_focused": true, "tabs": [{"is_active": true, "windows": [\#(window)]}]}]"#.utf8)
        XCTAssertEqual(KittyRemote.focusedWindowInfo(inLS: data)?.cwd, "/Users/me/proj")
    }

    func testNoFocusedOSWindowOrInactiveTabYieldsNothing() {
        XCTAssertNil(KittyRemote.focusedWindowSize(inLS: listing(osFocused: false)))
        XCTAssertNil(KittyRemote.focusedWindowSize(inLS: listing(tabActive: false)))
    }

    func testSplitsAreRefusedBecauseTheirGeometryIsUnknown() {
        XCTAssertNil(KittyRemote.focusedWindowSize(inLS: listing(windows: 2)))
    }

    func testGarbageListingYieldsNothing() {
        XCTAssertNil(KittyRemote.focusedWindowSize(inLS: Data("not json".utf8)))
    }

    func testScreenCombinesListingAndText() {
        var asked: [[String]] = []
        let screen = KittyRemote.screen { subcommand in
            asked.append(subcommand)
            return subcommand[0] == "ls" ? self.listing() : Data("hello\n".utf8)
        }
        XCTAssertEqual(screen, KittyRemote.Screen(ansiText: "hello\n", columns: 193, lines: 65))
        XCTAssertEqual(asked.last, ["get-text", "--match", "state:focused", "--ansi"])
    }

    func testOpenLinkAsksKittyToOpenTheURL() {
        var asked: [[String]] = []
        let opened = KittyRemote.openLink("https://example.com/x") { subcommand in
            asked.append(subcommand)
            return Data()
        }
        XCTAssertTrue(opened)
        XCTAssertEqual(asked, [["action", "open_url", "https://example.com/x"]])
        XCTAssertFalse(KittyRemote.openLink("https://example.com/x") { _ in nil })
    }

    func testScreenIsNilWhenKittenFails() {
        XCTAssertNil(KittyRemote.screen { _ in nil })
        XCTAssertNil(KittyRemote.screen { $0[0] == "ls" ? self.listing() : nil })
    }
}

/// File paths in screen text, and confirming them against the file system.
final class TerminalPathTests: XCTestCase {
    private func texts(_ text: String) -> [String] {
        TerminalLinks.findPaths(inANSI: text, columns: 80).map(\.text)
    }

    func testFindsAbsoluteHomeAndRelativePaths() {
        XCTAssertEqual(
            texts("see /etc/hosts and ~/src/a.txt, ./run.sh ../up/x.go src/main.swift"),
            ["/etc/hosts", "~/src/a.txt", "./run.sh", "../up/x.go", "src/main.swift"]
        )
    }

    func testBareFileNameNeedsAnExtension() {
        XCTAssertEqual(texts("edit Package.swift now"), ["Package.swift"])
    }

    func testLineAndColumnSuffixAreParsedAndLocated() {
        let found = TerminalLinks.findPaths(inANSI: "x src/a.swift:12:5: error", columns: 80)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].text, "src/a.swift")
        XCTAssertEqual(found[0].line, 12)
        XCTAssertEqual(found[0].column, 5)
        XCTAssertEqual(found[0].spans, [CellSpan(row: 0, startColumn: 2, endColumn: 18)])
    }

    func testLineWithoutColumn() {
        let found = TerminalLinks.findPaths(inANSI: "a/b.go:7:content", columns: 80)
        XCTAssertEqual(found.first?.line, 7)
        XCTAssertNil(found.first?.column)
    }

    func testTrailingSentencePunctuationIsDropped() {
        let found = TerminalLinks.findPaths(inANSI: "wrote /tmp/out.txt.", columns: 80)
        XCTAssertEqual(found.map(\.text), ["/tmp/out.txt"])
        XCTAssertEqual(found.first?.spans, [CellSpan(row: 0, startColumn: 6, endColumn: 18)])
    }

    func testURLsAreNotMistakenForPaths() {
        XCTAssertEqual(texts("open https://example.com/a/b.html please"), [])
    }

    func testHyperlinkLabelsAreSkipped() {
        let esc = "\u{1b}"
        let text = "\(esc)]8;;file:///tmp/a.txt\(esc)\\/tmp/a.txt\(esc)]8;;\(esc)\\ and /tmp/b.txt"
        XCTAssertEqual(texts(text), ["/tmp/b.txt"])
    }

    func testPathWrappedByTheTerminalKeepsASpanPerRow() {
        let found = TerminalLinks.findPaths(inANSI: "ab /usr/lib/xyz", columns: 8)
        XCTAssertEqual(found.first?.text, "/usr/lib/xyz")
        XCTAssertEqual(found.first?.spans, [
            CellSpan(row: 0, startColumn: 3, endColumn: 8), CellSpan(row: 1, startColumn: 0, endColumn: 7)
        ])
    }

    func testResolveExpandsHomeAndRelativeAgainstCwd() {
        let real: Set<String> = ["/Users/me/a.txt", "/proj/src/x.go", "/etc/hosts"]
        func resolve(_ text: String, cwd: String? = "/proj") -> String? {
            TerminalPathResolver.resolve(text, cwd: cwd, home: "/Users/me") { real.contains($0) }
        }
        XCTAssertEqual(resolve("~/a.txt"), "/Users/me/a.txt")
        XCTAssertEqual(resolve("src/x.go"), "/proj/src/x.go")
        XCTAssertEqual(resolve("./src/x.go"), "/proj/src/x.go")
        XCTAssertEqual(resolve("../src/x.go", cwd: "/proj/src"), "/proj/src/x.go")
        XCTAssertEqual(resolve("/etc/hosts"), "/etc/hosts")
        XCTAssertNil(resolve("and/or"))
        XCTAssertNil(resolve("src/x.go", cwd: nil))
    }
}

/// Kitty's window padding, which its AX text area includes.
final class KittyPaddingTests: XCTestCase {
    func testInsetShrinksTheTextAreaToTheCellGrid() {
        let padding = KittyPadding(left: 10, top: 4, right: 6, bottom: 8)
        XCTAssertEqual(
            padding.inset(CGRect(x: 100, y: 50, width: 800, height: 480)),
            CGRect(x: 110, y: 54, width: 784, height: 468)
        )
    }

    func testInsetIgnoresPaddingThatSwallowsTheArea() {
        let area = CGRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(KittyPadding(left: 8, top: 0, right: 8, bottom: 0).inset(area), area)
    }

    func testMeasuredPaddingBeyondTheConfigIsSplitEvenly() {
        XCTAssertEqual(
            KittyPadding.resolve(config: .zero, measuredHorizontal: 400, measuredVertical: 401),
            KittyPadding(left: 200, top: 200.5, right: 200, bottom: 200.5)
        )
    }

    func testConfigSplitWinsWhenItMatchesTheMeasurement() {
        let config = KittyPadding(left: 10, top: 4, right: 6, bottom: 8)
        XCTAssertEqual(KittyPadding.resolve(config: config, measuredHorizontal: 17, measuredVertical: 11), config)
    }

    func testMeasurementNoiseBelowZeroMeansNoPadding() {
        XCTAssertEqual(KittyPadding.resolve(config: .zero, measuredHorizontal: -1, measuredVertical: 0), .zero)
    }

    func testMeasuresPaddingFromTheFrameAndTheCellGridInPixels() {
        // A retina kitty window with 200pt set on every side (seen live).
        let measured = KittyPadding.measure(
            frame: CGRect(x: 0, y: 32, width: 1728, height: 1085),
            cellPixels: CGSize(width: 2652, height: 1369), scale: 2
        )
        XCTAssertEqual(measured.horizontal, 402)
        XCTAssertEqual(measured.vertical, 400.5)
    }

    func testReadsTheCellGridSizeFromATTY() throws {
        var ptyHost: Int32 = 0
        var ptyEnd: Int32 = 0
        var name = [CChar](repeating: 0, count: 128)
        var size = winsize(ws_row: 37, ws_col: 156, ws_xpixel: 2652, ws_ypixel: 1369)
        try XCTSkipIf(openpty(&ptyHost, &ptyEnd, &name, nil, &size) != 0, "no pty available")
        defer { close(ptyHost); close(ptyEnd) }
        XCTAssertEqual(
            KittyPadding.cellAreaInPixels(ttyPath: String(cString: name)),
            CGSize(width: 2652, height: 1369)
        )
    }

    func testATTYWithoutPixelSizesGivesNoCellGridSize() throws {
        var ptyHost: Int32 = 0
        var ptyEnd: Int32 = 0
        var name = [CChar](repeating: 0, count: 128)
        var size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        try XCTSkipIf(openpty(&ptyHost, &ptyEnd, &name, nil, &size) != 0, "no pty available")
        defer { close(ptyHost); close(ptyEnd) }
        XCTAssertNil(KittyPadding.cellAreaInPixels(ttyPath: String(cString: name)))
        XCTAssertNil(KittyPadding.cellAreaInPixels(ttyPath: "/dev/nonexistent"))
    }

    func testParsesTheEdgesFromKittysConfigLoader() {
        XCTAssertEqual(
            KittyPadding.parse(Data("[4.0, 12.0, 5.0, 13.0]".utf8)),
            KittyPadding(left: 4, top: 12, right: 5, bottom: 13)
        )
        XCTAssertNil(KittyPadding.parse(Data("oops".utf8)))
    }

    func testLaunchOptionsPickUpConfigAndOverrides() {
        let args = ["kitty", "--config", "/a.conf", "-c", "/b.conf", "--config=/c.conf",
                    "-o", "window_padding_width=12", "--override=font_size=14", "--listen-on", "unix:/x"]
        let options = KittyPadding.launchOptions(fromArguments: args)
        XCTAssertEqual(options.configs, ["/a.conf", "/b.conf", "/c.conf"])
        XCTAssertEqual(options.overrides, ["window_padding_width 12", "font_size 14"])
    }
}
