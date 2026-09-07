// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "keymonster",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
        // Sparkle drives in-app updates: it checks the appcast the Release
        // workflow publishes, verifies the DMG's EdDSA signature, and swaps
        // the bundle in place. Ships as a prebuilt xcframework.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0")
    ],
    targets: [
        .executableTarget(
            name: "keymonster",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/keymonster",
            // Sparkle.framework lives in Contents/Frameworks of the .app that
            // `make app` assembles; this rpath is how the binary finds it
            // there. SwiftPM adds its own rpath to the downloaded artifact,
            // which keeps `swift run` and `swift test` working.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        // A window of text fields to point text jump at by hand. Development
        // tooling: a separate executable, so it is never linked into the app
        // (`make app` copies only the keymonster binary into the bundle) and
        // never ships. See `make fixture`.
        .executableTarget(
            name: "axfixture",
            path: "Sources/axfixture"
        ),
        .testTarget(
            name: "keymonsterTests",
            dependencies: ["keymonster"],
            path: "Tests/keymonsterTests"
        )
    ]
)
