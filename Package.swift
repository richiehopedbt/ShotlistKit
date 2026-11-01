// swift-tools-version: 6.2
// ShotlistKit: the library an app links so Shotlist can capture its App Store screenshots.
// Every symbol is inside #if DEBUG, so Release builds contain none of it.
import CompilerPluginSupport
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
        // `@Shot`, which writes the app's body around its root view. A separate product because
        // it needs swift-syntax, which ShotlistKit doesn't.
        .library(name: "ShotlistMacros", targets: ["ShotlistMacros"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.17.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.26.0"),
        // For ShotlistMacros only; the same range swift-dependencies and TCA accept.
        .package(url: "https://github.com/swiftlang/swift-syntax", "600.0.0"..<"605.0.0"),
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
        .macro(
            name: "ShotlistMacroPlugin",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
        .target(name: "ShotlistMacros", dependencies: ["ShotlistKit", "ShotlistMacroPlugin"]),
        .testTarget(name: "ShotlistProtocolTests", dependencies: ["ShotlistProtocol"]),
        .testTarget(
            name: "ShotlistMacrosTests",
            dependencies: [
                "ShotlistMacroPlugin",
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
