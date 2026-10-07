import Foundation
import Testing

@testable import JerdDevKit

@Suite("Release run")
struct ReleaserTests {
    /// The Git and GitHub calls that change something, in order, as short labels.
    static func publicCalls(_ runner: FakeReleaseRunner) -> [String] {
        runner.recorded.compactMap { invocation in
            let arguments = invocation.arguments
            switch (invocation.executable.lastPathComponent, arguments.first) {
            case ("git", "commit"): return "commit"
            case ("git", "tag") where arguments.dropFirst().first == "-a": return "tag"
            case ("git", "push"): return "push \(arguments.last ?? "")"
            case ("gh", "release"): return "release \(arguments.dropFirst().first ?? "")"
            default: return nil
            }
        }
    }

    static let fullOrder = ["commit", "tag", "push refs/tags/v0.2.0", "release create", "push HEAD:main"]

    @Test("Publication runs the commit, the tag, the tag push, the GitHub release, and the push of main, in this order")
    func publicOrder() async throws {
        let workspace = try ReadyReleaseMac.workspace()
        defer { workspace.remove() }
        try await ReadyReleaseMac.releaser(workspace).run()
        #expect(Self.publicCalls(workspace.runner) == Self.fullOrder)
        #expect(workspace.runner.calls("git", ["commit"]) == [["commit", "--quiet", "-m", "Release v0.2.0"]])
        #expect(workspace.runner.calls("git", ["add"]).first?.suffix(3) == ArraySlice(ReleaseCommitFiles.paths))
        let create = try #require(workspace.runner.calls("gh", ["release", "create"]).first)
        #expect(create.contains("--verify-tag") && create.contains("Jerd 0.2.0"))
        #expect(create[3].hasSuffix(".build/releases/Jerd-0.2.0-3/Jerd-0.2.0.dmg"))
        #expect(create[4].hasSuffix("Jerd-0.2.0-3.dSYMs.zip"))
        #expect(workspace.output.all.contains("Released Jerd 0.2.0"))
    }

    @Test("The release commit writes the version, the promoted changelog, and the candidate feed")
    func commitFiles() async throws {
        let workspace = try ReadyReleaseMac.workspace()
        defer { workspace.remove() }
        try await ReadyReleaseMac.releaser(workspace).run()
        let version = try String(contentsOf: workspace.path("Configuration/Version.xcconfig"), encoding: .utf8)
        #expect(version == "// The app version.\nMARKETING_VERSION = 0.2.0\nCURRENT_PROJECT_VERSION = 3\n")
        let changelog = try String(contentsOf: workspace.path("CHANGELOG.md"), encoding: .utf8)
        #expect(changelog.contains("## [Unreleased]\n\n## [0.2.0] - 2026-10-06\n\n- New thing."))
        #expect(try Data(contentsOf: workspace.path("appcast.xml")) == Data("signed candidate feed\n".utf8))
    }

    @Test("--prepare-only builds the candidate, changes no tracked file, and never commits, pushes, or calls gh")
    func prepareOnly() async throws {
        let workspace = try ReadyReleaseMac.workspace()
        defer { workspace.remove() }
        workspace.runner.on("git", ["branch", "--show-current"], output: "feature\n")
        let before = try ReadyReleaseMac.trackedFiles(workspace)
        try await ReadyReleaseMac.releaser(workspace, prepareOnly: true).run()
        #expect(try ReadyReleaseMac.trackedFiles(workspace) == before)
        #expect(Self.publicCalls(workspace.runner).isEmpty)
        #expect(workspace.runner.calls("gh").isEmpty)
        #expect(workspace.runner.calls("git").allSatisfy { !["fetch", "ls-remote", "add"].contains($0.first) })
        #expect(FileManager.default.fileExists(atPath: workspace.path(".build/releases/Jerd-0.2.0-3/appcast.xml").path))
        #expect(workspace.output.all.contains("Nothing was published, and no tracked file changed."))
    }

    @Test("A failed local step publishes nothing and says so")
    func localFailure() async throws {
        let workspace = try ReadyReleaseMac.workspace()
        defer { workspace.remove() }
        let before = try ReadyReleaseMac.trackedFiles(workspace)
        await #expect(throws: DevFailure.self) {
            try await ReadyReleaseMac.releaser(workspace, failLocal: true).run()
        }
        #expect(Self.publicCalls(workspace.runner).isEmpty)
        #expect(try ReadyReleaseMac.trackedFiles(workspace) == before)
        #expect(workspace.output.all.contains("Nothing was published, and no tracked file changed."))
    }

    /// A failure of one public call, what still ran before it, and the recovery text that must follow.
    struct PublicFailure: CustomStringConvertible, Sendable {
        var description: String
        var program: String
        var prefix: [String]
        var calls: Int
        var recovery: [String]
    }

    static let publicFailures: [PublicFailure] = [
        PublicFailure(
            description: "the tag push", program: "git", prefix: ["push", "--quiet", "origin", "refs/tags/v0.2.0"],
            calls: 3,
            recovery: [
                "exist only on this Mac", "git ls-remote --tags origin v0.2.0", "git tag -d v0.2.0; git reset --hard",
            ]
        ),
        PublicFailure(
            description: "the GitHub release", program: "gh", prefix: ["release", "create"], calls: 4,
            recovery: [
                "The tag v0.2.0 is on GitHub", "gh release view v0.2.0", "--verify-tag --title \"Jerd 0.2.0\"",
                "git push origin :refs/tags/v0.2.0",
            ]),
        PublicFailure(
            description: "the push of main", program: "git", prefix: ["push", "--quiet", "origin", "HEAD:main"],
            calls: 5, recovery: ["The GitHub release v0.2.0 is public, but the feed is not", "git pull --no-rebase"]),
    ]

    @Test("A failed public step stops the run and prints what is public and the recovery", arguments: publicFailures)
    func publicFailure(_ failure: PublicFailure) async throws {
        let workspace = try ReadyReleaseMac.workspace()
        defer { workspace.remove() }
        workspace.runner.on(failure.program, failure.prefix, status: 1, error: "network down")
        await #expect(throws: DevFailure.self) { try await ReadyReleaseMac.releaser(workspace).run() }
        #expect(Self.publicCalls(workspace.runner) == Array(Self.fullOrder.prefix(failure.calls)))
        for text in failure.recovery {
            #expect(workspace.output.all.contains(text), "missing: \(text)")
        }
    }

    @Test("A commit that changed during the build stops before any file changes")
    func sourceChanged() async throws {
        let workspace = try ReadyReleaseMac.workspace()
        defer { workspace.remove() }
        let before = try ReadyReleaseMac.trackedFiles(workspace)
        var releaser = try ReadyReleaseMac.releaser(workspace)
        let local = releaser.localSteps
        let runner = workspace.runner
        releaser.localSteps = { builder in
            local(builder) + [
                ReleaseStep("Move HEAD") {
                    runner.on("git", ["rev-parse", "HEAD"], output: String(repeating: "c", count: 40) + "\n")
                }
            ]
        }
        await #expect(throws: DevFailure.self) { try await releaser.run() }
        #expect(Self.publicCalls(workspace.runner).isEmpty)
        #expect(try ReadyReleaseMac.trackedFiles(workspace) == before)
    }
}
