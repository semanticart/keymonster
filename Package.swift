// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "clipborg",
    platforms: [
        .macOS(.v14) // SwiftData requires macOS 14+
    ],
    targets: [
        .executableTarget(
            name: "clipborg",
            path: "Sources/clipborg"
        ),
        .testTarget(
            name: "clipborgTests",
            dependencies: ["clipborg"],
            path: "Tests/clipborgTests"
        )
    ]
)
