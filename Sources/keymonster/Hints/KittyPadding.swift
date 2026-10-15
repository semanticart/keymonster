import AppKit
import Darwin
import os.log

private let log = Logger(subsystem: "keymonster", category: "hints.kitty")

/// Kitty's `window_padding_width`, in points: blank margin between the window
/// edge and the cell grid. Kitty's accessibility text area covers the padding
/// too, so cell positions computed from its frame alone drift by the padding.
struct KittyPadding: Equatable {
    var left: CGFloat = 0
    var top: CGFloat = 0
    var right: CGFloat = 0
    var bottom: CGFloat = 0

    static let zero = KittyPadding()

    /// `rect` shrunk to the cell grid.
    func inset(_ rect: CGRect) -> CGRect {
        let width = rect.width - left - right
        let height = rect.height - top - bottom
        guard width > 0, height > 0 else { return rect }
        return CGRect(x: rect.minX + left, y: rect.minY + top, width: width, height: height)
    }

    /// How much wider and taller than the cell grid the text area `frame` (points)
    /// is, given the grid's size in pixels at `scale` pixels per point: the
    /// padding's totals per axis.
    static func measure(
        frame: CGRect, cellPixels: CGSize, scale: CGFloat
    ) -> (horizontal: CGFloat, vertical: CGFloat) {
        (frame.width - cellPixels.width / scale, frame.height - cellPixels.height / scale)
    }

    /// Combines the padding kitty's config says with what the window measures
    /// (the frame's size beyond its cell area, per axis, in points), so padding
    /// set at runtime (`kitten @ set-spacing`) counts. The config's split wins
    /// when its totals agree with the measurement; otherwise the measured total
    /// is split evenly, since only the sum can be seen.
    static func resolve(config: KittyPadding, measuredHorizontal: CGFloat, measuredVertical: CGFloat) -> KittyPadding {
        let tolerance: CGFloat = 3
        let horizontal = max(measuredHorizontal, 0)
        let vertical = max(measuredVertical, 0)
        var result = config
        if abs(config.left + config.right - horizontal) > tolerance {
            result.left = horizontal / 2
            result.right = horizontal / 2
        }
        if abs(config.top + config.bottom - vertical) > tolerance {
            result.top = vertical / 2
            result.bottom = vertical / 2
        }
        return result
    }

    /// The `[left, top, right, bottom]` JSON `effectiveScript` prints.
    static func parse(_ data: Data) -> KittyPadding? {
        guard let values = (try? JSONSerialization.jsonObject(with: data)) as? [Double],
              values.count == 4 else { return nil }
        return KittyPadding(
            left: CGFloat(values[0]), top: CGFloat(values[1]),
            right: CGFloat(values[2]), bottom: CGFloat(values[3])
        )
    }

    /// Asks kitty's own config loader, so `include`s, the config directory and
    /// the command line all count. Reads `KM_CFG` (--config paths) and `KM_OV`
    /// (--override lines) from the environment.
    static let effectiveScript = """
        import os,json; \
        from kitty.config import load_config; from kitty.cli import default_config_paths; \
        paths=default_config_paths(json.loads(os.environ.get("KM_CFG","[]"))); \
        e=load_config(*paths, overrides=json.loads(os.environ.get("KM_OV","[]"))).window_padding_width; \
        print(json.dumps([e.left,e.top,e.right,e.bottom]))
        """

    /// The `--config` paths and `--override` lines (`key value`) kitty was
    /// launched with.
    static func launchOptions(fromArguments arguments: [String]) -> (configs: [String], overrides: [String]) {
        var configs: [String] = []
        var overrides: [String] = []
        var index = 1
        func value(of argument: String, flags: [String]) -> String? {
            for flag in flags {
                if argument == flag, index + 1 < arguments.count {
                    index += 1
                    return arguments[index]
                }
                if flag.hasPrefix("--"), argument.hasPrefix(flag + "=") {
                    return String(argument.dropFirst(flag.count + 1))
                }
            }
            return nil
        }
        while index < arguments.count {
            let argument = arguments[index]
            if let path = value(of: argument, flags: ["--config", "-c"]) {
                configs.append(path)
            } else if let option = value(of: argument, flags: ["--override", "-o"]) {
                if let equals = option.firstIndex(of: "=") {
                    overrides.append(option.replacingCharacters(in: equals...equals, with: " "))
                } else {
                    overrides.append(option)
                }
            }
            index += 1
        }
        return (configs, overrides)
    }

    /// The padding of the running kitty `app`'s window whose text area is
    /// `frame`: the config's, corrected by measuring the window when a tty of
    /// its foreground group can be read. Re-read on every call (config about
    /// 50 ms) so config edits reloaded with ctrl+shift+f5 are picked up.
    static func of(_ app: NSRunningApplication, frame: CGRect, foregroundPIDs: [Int]) -> KittyPadding {
        let config = configured(app)
        guard let cells = cellAreaInPixels(foregroundPIDs: foregroundPIDs),
              let scale = backingScale(at: frame) else {
            log.debug("kitty padding: not measurable; using the config's")
            return config
        }
        let measured = measure(frame: frame, cellPixels: cells, scale: scale)
        let padding = resolve(
            config: config, measuredHorizontal: measured.horizontal, measuredVertical: measured.vertical
        )
        log.info("kitty padding: measured \(padding.left) \(padding.top) \(padding.right) \(padding.bottom)")
        return padding
    }

    private static func configured(_ app: NSRunningApplication) -> KittyPadding {
        let pid = app.processIdentifier
        guard let python = app.executableURL else { return .zero }
        let options = launchOptions(fromArguments: arguments(of: pid))
        var environment = ProcessInfo.processInfo.environment
        environment["KM_CFG"] = json(options.configs)
        environment["KM_OV"] = json(options.overrides)
        guard let data = KittyRemote.execute(
                  python, ["+runpy", effectiveScript], environment: environment, timeout: 3
              ),
              let padding = parse(data) else {
            log.error("couldn't read kitty's window padding; assuming none")
            return .zero
        }
        return padding
    }

    /// Backing scale of the screen holding the center of `frame` (AX
    /// coordinates: global, origin top-left of the primary screen).
    private static func backingScale(at frame: CGRect) -> CGFloat? {
        guard let primary = NSScreen.screens.first else { return nil }
        let center = CGPoint(x: frame.midX, y: primary.frame.height - frame.midY)
        return (NSScreen.screens.first { $0.frame.contains(center) } ?? primary).backingScaleFactor
    }

    /// The pixel size of the cell grid, as kitty reports it to programs in the
    /// window (`TIOCGWINSZ`) — it leaves the padding out.
    static func cellAreaInPixels(foregroundPIDs: [Int]) -> CGSize? {
        for pid in foregroundPIDs {
            if let path = ttyPath(of: pid_t(pid)), let size = cellAreaInPixels(ttyPath: path) { return size }
        }
        return nil
    }

    /// The pixel size the terminal behind the device at `path` reports.
    static func cellAreaInPixels(ttyPath path: String) -> CGSize? {
        let tty = open(path, O_RDONLY | O_NONBLOCK | O_NOCTTY)
        guard tty >= 0 else { return nil }
        defer { close(tty) }
        var size = winsize()
        guard ioctl(tty, TIOCGWINSZ, &size) == 0, size.ws_xpixel > 0, size.ws_ypixel > 0 else { return nil }
        return CGSize(width: CGFloat(size.ws_xpixel), height: CGFloat(size.ws_ypixel))
    }

    private static func ttyPath(of pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.e_tdev != UInt32.max,
              let name = devname(dev_t(info.e_tdev), S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    private static func json(_ strings: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: strings) else { return "[]" }
        return String(bytes: data, encoding: .utf8) ?? "[]"
    }

    /// `pid`'s argv, from the kernel (`KERN_PROCARGS2`): argc, the executable
    /// path, NUL padding, then the NUL-separated arguments.
    static func arguments(of pid: pid_t) -> [String] {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        let argc = Int(buffer.prefix(4).withUnsafeBytes { $0.load(as: Int32.self) })
        var parts = buffer[4..<size].split(separator: 0, omittingEmptySubsequences: false)
            .map { String(bytes: $0, encoding: .utf8) ?? "" }
        parts.removeFirst()  // executable path
        while parts.first?.isEmpty == true { parts.removeFirst() }
        return Array(parts.prefix(argc))
    }
}
