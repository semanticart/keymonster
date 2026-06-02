// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "clipborg",
    platforms: [
        .macOS(.v13) // MenuBarExtra requires macOS 13+
    ],
    targets: [
        .executableTarget(
            name: "clipborg",
            path: "Sources/clipborg"
        )
    ]
)
