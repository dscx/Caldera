// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Caldera",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Caldera",
            path: "Sources/Caldera"
        )
    ]
)
