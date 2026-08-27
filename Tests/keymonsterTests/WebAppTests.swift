import XCTest
@testable import keymonster

/// The bundle-based classification that drives hint-mode pre-warming and retry.
final class WebAppTests: XCTestCase {
    func testKnownChromiumBrowsersAreWebBacked() {
        XCTAssertTrue(WebApp.isWebBacked(bundleID: "com.google.Chrome", bundleURL: nil))
        XCTAssertTrue(WebApp.isWebBacked(bundleID: "com.brave.Browser", bundleURL: nil))
        XCTAssertTrue(WebApp.isWebBacked(bundleID: "com.microsoft.edgemac", bundleURL: nil))
    }

    func testNativeAppIsNotWebBacked() {
        XCTAssertFalse(WebApp.isWebBacked(bundleID: "com.apple.finder", bundleURL: nil))
        XCTAssertFalse(WebApp.isWebBacked(bundleID: nil, bundleURL: nil))
    }

    func testElectronFrameworkIsDetected() throws {
        // A minimal fake bundle shaped like an Electron app.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keymonster-webapp-\(UUID().uuidString)")
        let frameworks = root.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Bundle id unknown, but the Electron framework gives it away.
        XCTAssertTrue(WebApp.isWebBacked(bundleID: "com.tinyspeck.slackmacgap", bundleURL: root))
    }

    func testPlainBundleWithoutWebFrameworkIsNotWebBacked() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("keymonster-webapp-\(UUID().uuidString)")
        let frameworks = root.appendingPathComponent("Contents/Frameworks/Sparkle.framework")
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertFalse(WebApp.isWebBacked(bundleID: "com.example.NativeApp", bundleURL: root))
    }
}
