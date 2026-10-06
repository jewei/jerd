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
        module(
            "JerdUIFixtures", [
                "JerdUI", "JerdDesign", "JerdSnapshotSupport", "JerdFoundation", "JerdManifest", "JerdRuntimes",
                "JerdProcess", "JerdServiceKit", "JerdWeb", "JerdSystem", "JerdDatabases", "JerdMail", "JerdStorage",
            ],
            resources: [.copy("Resources/AppIcons")]),
        // Snapshot rendering and the component gallery. Only JerdSnapshots and tests import it; it never ships.
        module("JerdSnapshotSupport", ["JerdDesign"]),
        .executableTarget(name: "JerdSnapshots",
                          dependencies: ["JerdUI", "JerdUIFixtures", "JerdDesign", "JerdSnapshotSupport"],
                          swiftSettings: strictSettings),

        // Tests
        tests("JerdFoundation", []),
        tests("JerdProcess", ["JerdFoundation"], resources: [.copy("Fixtures")]),
        tests("JerdManifest", ["JerdFoundation"], resources: [.copy("Fixtures")]),
        tests("JerdArchive", ["JerdFoundation"]),
        tests(
            "JerdRuntimes", ["JerdFoundation", "JerdProcess", "JerdManifest", "JerdArchive"],
            resources: [.copy("Fixtures")]),
        tests("JerdSystem", ["JerdFoundation"], resources: [.copy("Fixtures")]),
        tests("JerdHelperCore", ["JerdFoundation", "JerdSystem"], resources: [.copy("Fixtures")]),
        // Opt-in signed XPC check; SignedXPCCheckTests runs it when JERD_XPC_IDENTITY is set.
        .executableTarget(name: "JerdXPCCheck", dependencies: ["JerdFoundation", "JerdSystem"],
                          path: "Tests/JerdXPCCheck", swiftSettings: strictSettings),
        tests("JerdWeb", ["JerdFoundation", "JerdProcess"], resources: [.copy("Fixtures")]),
        tests("JerdCLICore", ["JerdFoundation", "JerdRuntimes", "JerdWeb"]),
        // Fakes and C fixtures that the service test targets share. Only test targets depend on it.
        .target(
            name: "JerdServiceKitTestSupport", dependencies: ["JerdFoundation", "JerdProcess", "JerdServiceKit"],
            path: "Tests/JerdServiceKitTestSupport", resources: [.copy("Fixtures")], swiftSettings: strictSettings),
        tests("JerdServiceKit", ["JerdFoundation", "JerdProcess", "JerdServiceKitTestSupport"]),
        tests(
            "JerdDatabases", ["JerdFoundation", "JerdProcess", "JerdServiceKit", "JerdServiceKitTestSupport"],
            resources: [.copy("Fixtures")]),
        tests(
            "JerdMail", ["JerdFoundation", "JerdProcess", "JerdServiceKit", "JerdServiceKitTestSupport"],
            resources: [.copy("Fixtures")]),
        tests(
            "JerdStorage", ["JerdFoundation", "JerdProcess", "JerdServiceKit", "JerdServiceKitTestSupport"],
            resources: [.copy("Fixtures")]),
        tests("JerdTunnels", ["JerdFoundation", "JerdProcess"]),
        tests("JerdDesign", ["JerdSnapshotSupport"]),
        tests("JerdSnapshotSupport", ["JerdDesign"]),
        tests(
            "JerdUI", [
                "JerdUIFixtures", "JerdDesign", "JerdFoundation", "JerdSnapshotSupport", "JerdManifest", "JerdRuntimes",
                "JerdProcess", "JerdServiceKit", "JerdWeb", "JerdSystem", "JerdDatabases", "JerdMail", "JerdStorage",
            ]),
        tests("JerdLive", ["JerdUI", "JerdFoundation"]),
    ]
)
