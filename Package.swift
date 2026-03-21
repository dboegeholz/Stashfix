// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stashfix",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Stashfix",
            path: "Sources/Stashfix"
        )
    ]
)
