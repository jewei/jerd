// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JerdCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "JerdCore", targets: ["JerdCore"])],
    targets: [
        .target(name: "JerdCore"),
        .testTarget(name: "JerdCoreTests", dependencies: ["JerdCore"],
                    resources: [.copy("Fixtures")])
    ]
)
