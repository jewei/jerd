// swift-tools-version: 6.0
import PackageDescription

// The jerd-dev tool behind `./dev`. All logic is in JerdDevKit so that tests can use it.
// JerdKit supplies the formats and rules that the app and the tool share: runtime pins, payload
// receipts, the preparation pipeline, and the appcast verifier.

let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny")
]

let package = Package(
    name: "JerdTools",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "jerd-dev", targets: ["JerdDev"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
        .package(path: "../Packages/JerdKit"),
    ],
    targets: [
        .target(
            name: "JerdDevKit",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "JerdManifest", package: "JerdKit"),
                .product(name: "JerdRuntimes", package: "JerdKit"),
            ],
            swiftSettings: strictSettings
        ),
        .executableTarget(name: "JerdDev", dependencies: ["JerdDevKit"], swiftSettings: strictSettings),
        .testTarget(name: "JerdDevKitTests", dependencies: ["JerdDevKit"], swiftSettings: strictSettings),
    ]
)
