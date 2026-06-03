// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "clipborg",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .executableTarget(
            name: "clipborg",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/clipborg"
        ),
        .testTarget(
            name: "clipborgTests",
            dependencies: ["clipborg"],
            path: "Tests/clipborgTests"
        )
    ]
)
