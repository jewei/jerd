// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JerdCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "JerdCore", targets: ["JerdCore"])],
    targets: [
        .systemLibrary(name: "CArchive"),
        .target(name: "JerdCore", dependencies: ["CArchive"]),
        .testTarget(name: "JerdCoreTests", dependencies: ["JerdCore"],
                    resources: [.copy("Fixtures")])
    ]
)
