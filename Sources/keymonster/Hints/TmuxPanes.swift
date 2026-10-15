import AppKit
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints.tmux")

/// Where tmux put its panes, so scroll mode can aim wheel events at the
/// active one. Kitty shows a tmux window as one opaque text area; wheel events
/// land on whichever pane is under the pointer, so the pointer has to go to
/// the pane's cells rather than the middle of the whole grid.
enum TmuxPanes {
    /// A pane's place in the tmux window, in cells.
    struct Pane: Equatable {
        let left: Int
        let top: Int
        let width: Int
        let height: Int
        let isActive: Bool
        /// The window is zoomed on some pane, hiding the rest.
        var windowZoomed = false
    }

    /// The `-F` format `parse` reads.
    static let format = "#{pane_active} #{pane_left} #{pane_top} #{pane_width} #{pane_height} #{window_zoomed_flag}"

    static func parse(_ output: String) -> [Pane] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ").compactMap { Int($0) }
            guard fields.count == 6, fields[3] > 0, fields[4] > 0 else { return nil }
            return Pane(left: fields[1], top: fields[2], width: fields[3], height: fields[4],
                        isActive: fields[0] == 1, windowZoomed: fields[5] == 1)
        }
    }

    /// The panes' rects on screen, given the kitty text area they are drawn
    /// in, active pane first. A zoomed window shows only its active pane.
    static func frames(of panes: [Pane], in grid: TerminalGrid) -> [CGRect] {
        let cellWidth = grid.frame.width / CGFloat(max(grid.columns, 1))
        let cellHeight = grid.frame.height / CGFloat(max(grid.lines, 1))
        let visible = panes.contains(where: \.windowZoomed) ? panes.filter(\.isActive) : panes
        return (visible.filter(\.isActive) + visible.filter { !$0.isActive }).map { pane in
            CGRect(
                x: grid.frame.minX + CGFloat(pane.left) * cellWidth,
                y: grid.frame.minY + CGFloat(pane.top) * cellHeight,
                width: CGFloat(pane.width) * cellWidth,
                height: CGFloat(pane.height) * cellHeight
            )
        }
    }

    /// The tmux client among `pids` (the kitty window's foreground processes),
    /// from `tmux list-clients -F "#{client_pid} #{window_id}"` output, as the
    /// id of the window that client is looking at.
    static func window(forClientIn pids: [Int], clients: String) -> String? {
        for line in clients.split(separator: "\n") {
            let fields = line.split(separator: " ")
            if fields.count == 2, let pid = Int(fields[0]), pids.contains(pid) {
                return String(fields[1])
            }
        }
        return nil
    }

    /// Runs one tmux subcommand and returns its stdout, nil on failure.
    typealias Runner = (_ arguments: [String]) -> Data?

    /// The pane frames (active first) for a kitty window whose foreground
    /// processes are `pids`; nil when none of them is a tmux client, so callers
    /// fall back to treating the window as one pane.
    static func frames(foregroundPIDs pids: [Int], grid: TerminalGrid, run: Runner) -> [CGRect]? {
        guard let clients = run(["list-clients", "-F", "#{client_pid} #{window_id}"])
                .flatMap({ String(bytes: $0, encoding: .utf8) }),
              let window = window(forClientIn: pids, clients: clients),
              let listing = run(["list-panes", "-t", window, "-F", format])
                .flatMap({ String(bytes: $0, encoding: .utf8) }) else {
            return nil
        }
        let frames = frames(of: parse(listing), in: grid)
        return frames.isEmpty ? nil : frames
    }

    private static let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]

    /// A runner for the tmux binary, or nil when none is installed in a usual place.
    static func runner(timeout: TimeInterval = 1) -> Runner? {
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        return { KittyRemote.execute(url, $0, timeout: timeout) }
    }
}

/// Splits scroll mode's one kitty pane into the tmux panes inside it.
@MainActor
enum KittyTmuxScroll {
    /// The tmux panes' frames (active first) inside the frontmost kitty
    /// window, or nil when kitty isn't running tmux there (or can't be asked).
    static func frames(in app: NSRunningApplication, textArea: CGRect) -> [CGRect]? {
        guard app.bundleIdentifier == KittyRemote.bundleID,
              let kitty = KittyRemote.runner(for: app),
              let listing = kitty(["ls"]),
              let window = KittyRemote.focusedWindowInfo(inLS: listing),
              !window.foregroundPIDs.isEmpty,
              let tmux = TmuxPanes.runner() else {
            return nil
        }
        let padding = KittyPadding.of(app, frame: textArea, foregroundPIDs: window.foregroundPIDs)
        let grid = TerminalGrid(frame: padding.inset(textArea), columns: window.columns, lines: window.lines)
        let frames = TmuxPanes.frames(foregroundPIDs: window.foregroundPIDs, grid: grid, run: tmux)
        log.debug("tmux panes: \(frames?.count ?? 0)")
        return frames
    }
}
