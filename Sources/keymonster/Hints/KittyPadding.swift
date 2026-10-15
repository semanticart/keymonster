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

    private static let cache = OSAllocatedUnfairLock(initialState: [pid_t: KittyPadding]())

    /// The padding of the running kitty `app`, cached per process.
    static func of(_ app: NSRunningApplication) -> KittyPadding {
        let pid = app.processIdentifier
        if let cached = cache.withLock({ $0[pid] }) { return cached }
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
        cache.withLock { $0[pid] = padding }
        return padding
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
