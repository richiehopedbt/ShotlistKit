// swift-tools-version: 6.2
// ShotlistKit: the library an app links so Shotlist can capture its App Store screenshots.
// Every symbol is inside #if DEBUG, so Release builds contain none of it.
import PackageDescription

let package = Package(
    name: "ShotlistKit",
    platforms: [.iOS(.v17), .macOS(.v15)],
    products: [
        .library(name: "ShotlistKit", targets: ["ShotlistKit"]),
        // For apps that use swift-dependencies: pins date, uuid, clock and locale per scene.
        .library(name: "ShotlistDependencies", targets: ["ShotlistDependencies"]),
        // For apps built with the Composable Architecture: TCAScene.
        .library(name: "ShotlistTCA", targets: ["ShotlistTCA"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.26.0"),
    ],
    targets: [
        // The wire protocol between the app and the Shotlist engine.
        .target(name: "ShotlistProtocol"),
        .target(name: "ShotlistKit", dependencies: ["ShotlistProtocol"]),
        .target(
            name: "ShotlistDependencies",
            dependencies: ["ShotlistKit", .product(name: "Dependencies", package: "swift-dependencies")]
        ),
        .target(
            name: "ShotlistTCA",
            dependencies: [
                "ShotlistKit",
                "ShotlistDependencies",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),
        .testTarget(name: "ShotlistProtocolTests", dependencies: ["ShotlistProtocol"]),
    ],
    swiftLanguageModes: [.v6]
)
