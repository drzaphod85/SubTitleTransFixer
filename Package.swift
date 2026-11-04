// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SubTitleTransFixer",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SubTitleTransFixer",
            path: "Sources/SubTitleTransFixer"
        )
    ]
)
