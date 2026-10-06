import Foundation
import Testing

@testable import JerdDevKit

@Suite("Release version bump")
struct VersionBumpTests {
    @Test("Sets the version file and promotes the changelog without other changes")
    func bumps() throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        let changed = try VersionBump(environment: workspace.environment())
            .run(version: #require(.release("0.2.0")), build: 3)
        #expect(changed == ["Configuration/Version.xcconfig", "CHANGELOG.md"])
        let version = try String(contentsOf: workspace.path("Configuration/Version.xcconfig"), encoding: .utf8)
        #expect(version == "// The app version.\nMARKETING_VERSION = 0.2.0\nCURRENT_PROJECT_VERSION = 3\n")
        let changelog = try String(contentsOf: workspace.path("CHANGELOG.md"), encoding: .utf8)
        #expect(changelog.contains("## [Unreleased]\n\n## [0.2.0] - 2026-10-06\n\n- New thing."))
        #expect(workspace.runner.recorded.isEmpty)
    }

    @Test("Refuses a build that does not grow and leaves the files unchanged")
    func refusesLowerBuild() throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        let before = try Data(contentsOf: workspace.path("Configuration/Version.xcconfig"))
        #expect(throws: DevFailure.self) {
            try VersionBump(environment: workspace.environment()).run(version: #require(.release("0.2.0")), build: 2)
        }
        #expect(try Data(contentsOf: workspace.path("Configuration/Version.xcconfig")) == before)
    }

    @Test("Refuses a committed feed that is not signed with the key")
    func refusesUnsignedFeed() throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        try workspace.write(ReleaseWorkspace.emptyFeed, to: "appcast.xml")
        #expect(throws: DevFailure.self) {
            try VersionBump(environment: workspace.environment()).run(version: #require(.release("0.2.0")), build: 3)
        }
    }

    @Test("Refuses a version file with a conditional version")
    func refusesConditionalVersion() throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        try workspace.write(
            "MARKETING_VERSION = 0.1.0\nMARKETING_VERSION[config=Debug] = 9\nCURRENT_PROJECT_VERSION = 2\n",
            to: "Configuration/Version.xcconfig")
        #expect(throws: DevFailure.self) {
            try VersionBump(environment: workspace.environment()).run(version: #require(.release("0.2.0")), build: 3)
        }
    }
}
