import AppKit

/// A terminal instance the app started for an edit, and so may quit.
/// `NSRunningApplication` in production; a fake in tests.
protocol TerminalInstance: AnyObject {
    var processIdentifier: pid_t { get }
    @discardableResult func terminate() -> Bool
}

extension NSRunningApplication: TerminalInstance {}

/// Opens a terminal app on the wrapper script through Launch Services, so the
/// window comes forward like a user-launched one. Returns the instance started
/// for the edit — the one to quit when it's over — or nil when the script was
/// handed to the app as a document, since that app may well have been the
/// user's running one.
enum TerminalOpener {
    static func open(_ launch: TerminalLaunch, app appURL: URL, script scriptPath: String) async throws
        -> TerminalInstance? {
        let configuration = NSWorkspace.OpenConfiguration()
        switch launch {
        case .newInstance(let arguments):
            // A running instance would only be activated and the arguments
            // dropped, so ask for a new one.
            configuration.createsNewApplicationInstance = true
            configuration.arguments = arguments
            return try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        case .document:
            _ = try await NSWorkspace.shared.open(
                [URL(fileURLWithPath: scriptPath)], withApplicationAt: appURL, configuration: configuration
            )
            return nil
        }
    }
}
