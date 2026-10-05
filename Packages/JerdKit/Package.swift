// swift-tools-version: 6.0
import PackageDescription

// Each target owns one responsibility. A target may depend only on the targets
// listed for it here. See Docs/Architecture.md for the dependency rules.

let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

// Every library target keeps a README.md beside its sources. SwiftPM must not treat it as a resource.
func module(_ name: String, _ dependencies: [Target.Dependency] = [], resources: [Resource]? = nil) -> Target {
    .target(name: name, dependencies: dependencies, exclude: ["README.md"], resources: resources,
            swiftSettings: strictSettings)
}

func tests(_ name: String, _ dependencies: [Target.Dependency], resources: [Resource]? = nil) -> Target {
    .testTarget(name: "\(name)Tests", dependencies: [.target(name: name)] + dependencies,
                resources: resources, swiftSettings: strictSettings)
}

let package = Package(
    name: "JerdKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JerdUI", targets: ["JerdUI"]),
        .library(name: "JerdLive", targets: ["JerdLive"]),
        .library(name: "JerdHelperCore", targets: ["JerdHelperCore"]),
        .library(name: "JerdCLICore", targets: ["JerdCLICore"]),
        .library(name: "JerdManifest", targets: ["JerdManifest"]),
        .library(name: "JerdRuntimes", targets: ["JerdRuntimes"]),
        .executable(name: "jerd-snapshots", targets: ["JerdSnapshots"]),
    ],
    targets: [
        .systemLibrary(name: "CArchive"),

        // Foundation layers
        module("JerdFoundation"),
        module("JerdProcess", ["JerdFoundation"]),
        module("JerdManifest", ["JerdFoundation"]),
        module("JerdArchive", ["CArchive", "JerdFoundation"]),

        // Runtime supply
        module("JerdRuntimes", ["JerdFoundation", "JerdProcess", "JerdManifest", "JerdArchive"]),

        // Privileged system integration
        module("JerdSystem", ["JerdFoundation"]),
        module("JerdHelperCore", ["JerdFoundation", "JerdSystem"]),

        // Web serving and command-line tools
        module("JerdWeb", ["JerdFoundation", "JerdProcess"]),
        module("JerdCLICore", ["JerdFoundation", "JerdRuntimes", "JerdWeb"]),

        // Managed data services
        module("JerdServiceKit", ["JerdFoundation", "JerdProcess"]),
        module("JerdDatabases", ["JerdFoundation", "JerdProcess", "JerdServiceKit"]),
        module("JerdMail", ["JerdFoundation", "JerdProcess", "JerdServiceKit"]),
        module("JerdStorage", ["JerdFoundation", "JerdProcess", "JerdServiceKit"]),
        module("JerdTunnels", ["JerdFoundation", "JerdProcess"]),

        // Interface
        module("JerdDesign"),
        module("JerdUI", [
            "JerdDesign", "JerdFoundation", "JerdProcess", "JerdManifest", "JerdRuntimes", "JerdSystem",
            "JerdWeb", "JerdServiceKit", "JerdDatabases", "JerdMail", "JerdStorage", "JerdTunnels",
        ]),
        module("JerdLive", [
            "JerdUI", "JerdFoundation", "JerdProcess", "JerdManifest", "JerdRuntimes", "JerdSystem",
            "JerdWeb", "JerdCLICore", "JerdServiceKit", "JerdDatabases", "JerdMail", "JerdStorage", "JerdTunnels",
        ]),
        module("JerdUIFixtures", ["JerdUI", "JerdDesign"]),
        // Snapshot rendering and the component gallery. Only JerdSnapshots and tests import it; it never ships.
        module("JerdSnapshotSupport", ["JerdDesign"]),
        .executableTarget(name: "JerdSnapshots",
                          dependencies: ["JerdUI", "JerdUIFixtures", "JerdDesign", "JerdSnapshotSupport"],
                          swiftSettings: strictSettings),

        // Tests
        tests("JerdFoundation", []),
        tests("JerdProcess", ["JerdFoundation"], resources: [.copy("Fixtures")]),
        tests("JerdManifest", ["JerdFoundation"]),
        tests("JerdArchive", ["JerdFoundation"]),
        tests("JerdRuntimes", ["JerdFoundation", "JerdProcess", "JerdManifest", "JerdArchive"]),
        tests("JerdSystem", ["JerdFoundation"]),
        tests("JerdHelperCore", ["JerdFoundation", "JerdSystem"]),
        tests("JerdWeb", ["JerdFoundation", "JerdProcess"]),
        tests("JerdCLICore", ["JerdFoundation", "JerdRuntimes", "JerdWeb"]),
        tests("JerdServiceKit", ["JerdFoundation", "JerdProcess"]),
        tests("JerdDatabases", ["JerdFoundation", "JerdProcess", "JerdServiceKit"]),
        tests("JerdMail", ["JerdFoundation", "JerdProcess", "JerdServiceKit"]),
        tests("JerdStorage", ["JerdFoundation", "JerdProcess", "JerdServiceKit"]),
        tests("JerdTunnels", ["JerdFoundation", "JerdProcess"]),
        tests("JerdDesign", ["JerdSnapshotSupport"]),
        tests("JerdSnapshotSupport", ["JerdDesign"]),
        tests("JerdUI", ["JerdUIFixtures", "JerdDesign", "JerdFoundation"]),
        tests("JerdLive", ["JerdUI", "JerdFoundation"]),
    ]
)
