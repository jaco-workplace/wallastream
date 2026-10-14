// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wallastream",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(
            name: "Wallastream",
            path: "Sources/Wallastream",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
