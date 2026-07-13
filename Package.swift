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
        .testTarget(
            name: "keymonsterTests",
            dependencies: ["keymonster"],
            path: "Tests/keymonsterTests"
        )
    ]
)
