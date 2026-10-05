// swift-tools-version: 6.0
import PackageDescription

// The jerd-dev tool behind `./dev`. All logic is in JerdDevKit so that tests can
// use it. Later commands (`runtimes`, `release`) add a dependency on
// `.package(path: "../Packages/JerdKit")` for the JerdManifest and JerdRuntimes
// products, and one file each in Sources/JerdDevKit/Commands.

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
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2")
    ],
    targets: [
        .target(
            name: "JerdDevKit",
            dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")],
            swiftSettings: strictSettings
        ),
        .executableTarget(name: "JerdDev", dependencies: ["JerdDevKit"], swiftSettings: strictSettings),
        .testTarget(name: "JerdDevKitTests", dependencies: ["JerdDevKit"], swiftSettings: strictSettings),
    ]
)
