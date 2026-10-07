import Foundation
import JerdManifest
import Testing

@testable import JerdDevKit

@Suite("Release preconditions")
struct ReleasePreconditionsTests {
    /// One change to a ready Mac and a part of the message that the refusal must give.
    struct Refusal: CustomStringConvertible, Sendable {
        var description: String
        var message: String
        var change: @Sendable (ReleaseWorkspace) throws -> Void
    }

    static let refusals: [Refusal] = [
        Refusal(description: "another branch", message: "main branch") {
            $0.runner.on("git", ["branch", "--show-current"], output: "feature\n")
        },
        Refusal(description: "a dirty tree", message: "clean worktree") {
            $0.runner.on("git", ["status"], output: "?? new-file\n")
        },
        Refusal(description: "HEAD behind origin/main", message: "HEAD is not origin/main") {
            $0.runner.on("git", ["rev-parse", "refs/remotes/origin/main"], output: String(repeating: "b", count: 40))
        },
        Refusal(description: "another origin", message: "origin remote") {
            $0.runner.on("git", ["remote", "get-url", "origin"], output: "https://example.com/fork.git\n")
        },
        Refusal(description: "no CI result", message: "has no ./dev check result") {
            $0.runner.on("gh", ["api", ReadyReleaseMac.checkRuns], output: "")
        },
        Refusal(description: "a failed CI run", message: "no successful ./dev check run (failure)") {
            $0.runner.on(
                "gh", ["api", ReadyReleaseMac.checkRuns],
                output: #"{"name":"./dev check","status":"completed","conclusion":"failure"}"#)
        },
        Refusal(description: "a running CI run", message: "not finished") {
            $0.runner.on(
                "gh", ["api", ReadyReleaseMac.checkRuns],
                output: #"{"name":"./dev check","status":"in_progress","conclusion":null}"#)
        },
        Refusal(description: "a local tag", message: "exists on this Mac") {
            $0.runner.on("git", ["tag", "--list", "v0.2.0"], output: "v0.2.0\n")
        },
        Refusal(description: "a tag on GitHub", message: "exists on GitHub") {
            $0.runner.on("git", ["ls-remote"], status: 0, output: "abc\trefs/tags/v0.2.0\n")
        },
        Refusal(description: "no answer about the tag", message: "Could not ask GitHub") {
            $0.runner.on("git", ["ls-remote"], status: 128, error: "fatal: unable to access")
        },
        Refusal(description: "a draft release", message: "A draft release named v0.2.0") {
            $0.runner.on("gh", ["api", "repos/jewei/jerd/releases"], output: #"{"tag":"v0.2.0","draft":true}"#)
        },
        Refusal(description: "a public release", message: "A release named v0.2.0 exists on GitHub") {
            $0.runner.on("gh", ["api", "repos/jewei/jerd/releases"], output: #"{"tag":"v0.2.0","draft":false}"#)
        },
        Refusal(description: "a detached HEAD", message: "not a detached HEAD") {
            $0.runner.on("git", ["branch", "--show-current"], output: "\n")
        },
        Refusal(description: "a version that the feed has", message: "VERSION 0.2.0 must exceed the version 0.2.0") {
            try ReleasePreconditionsTests.writeFeed(build: 2, version: "0.2.0", in: $0)
        },
        Refusal(description: "no unreleased notes", message: "Add release notes") {
            try $0.write("# Changelog\n\n## [Unreleased]\n\n", to: "CHANGELOG.md")
        },
        Refusal(description: "notes that are not plain text", message: "plain text") {
            try $0.write("# Changelog\n\n## [Unreleased]\n\n- Uses `code`.\n", to: "CHANGELOG.md")
        },
        Refusal(description: "a build below the version file", message: "BUILD must be 4 or greater") {
            try $0.write(
                "MARKETING_VERSION = 0.1.0\nCURRENT_PROJECT_VERSION = 4\n", to: "Configuration/Version.xcconfig")
        },
        Refusal(description: "the build of a released version", message: "which is released") {
            try $0.write(
                "MARKETING_VERSION = 0.1.0\nCURRENT_PROJECT_VERSION = 3\n", to: "Configuration/Version.xcconfig")
            $0.runner.on("git", ["tag", "--list", "v0.1.0"], output: "v0.1.0\n")
        },
        Refusal(description: "a lower version than the version file", message: "VERSION must not be lower") {
            try $0.write(
                "MARKETING_VERSION = 0.3.0\nCURRENT_PROJECT_VERSION = 2\n", to: "Configuration/Version.xcconfig")
        },
        Refusal(description: "a build that the feed has", message: "must exceed the build 3 in appcast.xml") {
            try ReleasePreconditionsTests.writeFeed(build: 3, version: "0.1.5", in: $0)
        },
    ]

    /// A committed feed with one item, signed with the test key.
    static func writeFeed(build: Int, version: String, in workspace: ReleaseWorkspace) throws {
        let item = AppcastWriter.Item(
            version: ReleaseVersion.release(version)!, build: build, minimumMacOS: ReleaseVersion("14.0")!,
            notes: "- Old.\n", publishedAt: Date(timeIntervalSince1970: 0), archiveLength: 1,
            archiveSignature: try workspace.key.signature(of: Data("x".utf8)))
        let feed = try AppcastWriter.feed(from: Data(ReleaseWorkspace.emptyFeed.utf8), adding: item)
        try workspace.key.signedFeed(feed).write(to: workspace.path("appcast.xml"))
    }

    @Test("A ready Mac passes and gives the commit, the unreleased notes, and the files of the release commit")
    func passes() async throws {
        let workspace = try ReadyReleaseMac.workspace()
        defer { workspace.remove() }
        let source = try await ReadyReleaseMac.preconditions(workspace).check()
        #expect(source.commit == ReleaseFixtures.commit)
        #expect(source.notes == "- New thing.\n")
        #expect(source.changelog == ReleaseWorkspace.changelog)
        #expect(workspace.runner.calls("git", ["fetch"]) == [["fetch", "--quiet", "--tags", "origin", "main"]])
    }

    @Test("Each precondition refuses with a message that names the cause", arguments: refusals)
    func refuses(_ refusal: Refusal) async throws {
        let workspace = try ReadyReleaseMac.workspace()
        defer { workspace.remove() }
        try refusal.change(workspace)
        let preconditions = try ReadyReleaseMac.preconditions(workspace)
        let error = await #expect(throws: DevFailure.self) { _ = try await preconditions.check() }
        #expect(error?.message.contains(refusal.message) == true, "\(error?.message ?? "no error")")
    }

    @Test("A build equal to an unreleased version file is accepted")
    func acceptsUnreleasedBuild() async throws {
        let workspace = try ReadyReleaseMac.workspace()
        defer { workspace.remove() }
        try workspace.write(
            "MARKETING_VERSION = 0.1.0\nCURRENT_PROJECT_VERSION = 3\n", to: "Configuration/Version.xcconfig")
        _ = try await ReadyReleaseMac.preconditions(workspace).check()
    }

    @Test("--prepare-only allows any branch and never asks GitHub")
    func prepareOnlyStaysLocal() async throws {
        let workspace = try ReadyReleaseMac.workspace()
        defer { workspace.remove() }
        workspace.runner.on("git", ["branch", "--show-current"], output: "feature\n")
        workspace.runner.on("gh", status: 1, error: "must not run")
        _ = try await ReadyReleaseMac.preconditions(workspace, prepareOnly: true).check()
        #expect(workspace.runner.calls("gh").isEmpty)
        let network = workspace.runner.calls("git").filter { ["fetch", "ls-remote", "push"].contains($0.first) }
        #expect(network.isEmpty)
    }

    @Test("--prepare-only still refuses a dirty tree, a local tag, and bad notes")
    func prepareOnlyKeepsLocalChecks() async throws {
        for refusal in Self.refusals
        where ["a dirty tree", "a local tag", "notes that are not plain text"].contains(refusal.description) {
            let workspace = try ReadyReleaseMac.workspace()
            defer { workspace.remove() }
            try refusal.change(workspace)
            let preconditions = try ReadyReleaseMac.preconditions(workspace, prepareOnly: true)
            await #expect(throws: DevFailure.self) { _ = try await preconditions.check() }
        }
    }

    @Test("The preflight checks the Keychain key, the notary profile, and the embedded payloads")
    func preflight() async throws {
        let workspace = try ReadyReleaseMac.workspace()
        defer { workspace.remove() }
        try await ReleasePreflight(shell: workspace.shell(), inputs: ReleaseFixtures.inputs()).run()
        let notary = try #require(workspace.runner.calls("xcrun", ["notarytool", "history"]).first)
        #expect(notary == ["notarytool", "history", "--keychain-profile", "notary", "--output-format", "json"])
        #expect(workspace.runner.calls("generate_keys") == [["--account", "dev.jerd.sparkle", "-p"]])
    }

    @Test("The preflight refuses another Sparkle key and a missing embedded payload")
    func preflightRefusals() async throws {
        let key = try ReadyReleaseMac.workspace()
        defer { key.remove() }
        key.runner.on("generate_keys", output: "AAAA\n")
        await #expect(throws: DevFailure.self) {
            try await ReleasePreflight(shell: key.shell(), inputs: ReleaseFixtures.inputs()).run()
        }
        let payload = try ReadyReleaseMac.workspace()
        defer { payload.remove() }
        try FileManager.default.removeItem(at: payload.path(".build/runtimes/payloads/mail"))
        let error = await #expect(throws: DevFailure.self) {
            try await ReleasePreflight(shell: payload.shell(), inputs: ReleaseFixtures.inputs()).run()
        }
        #expect(error?.message.contains("mailpit-") == true)
    }
}
