// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Undertextaren",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Undertextaren",
            path: "Sources/Undertextaren"
        )
    ]
)
