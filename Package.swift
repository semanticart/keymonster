// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "keymonster",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .executableTarget(
            name: "keymonster",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/keymonster"
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
