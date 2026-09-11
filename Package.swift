// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TempBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TempBar",
            path: "Sources/TempBar"
        )
    ]
)
