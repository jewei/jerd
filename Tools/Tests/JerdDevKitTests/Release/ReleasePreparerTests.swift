import Foundation
import JerdManifest
import Testing

@testable import JerdDevKit

@Suite("Release preparation")
struct ReleasePreparerTests {
    /// A bumped workspace (0.2.0, build 3, notes) whose tools answer like a ready release Mac.
    static func readyWorkspace() throws -> ReleaseWorkspace {
        let workspace = try ReleaseWorkspace(version: "0.2.0", build: "3")
        try workspace.write(
            "# Changelog\n\n## [Unreleased]\n\n## [0.2.0] - 2026-10-06\n\n- New thing.\n", to: "CHANGELOG.md")
        try PayloadFixture.write(to: workspace.path(".build/runtimes/payloads"))
        workspace.runner.on("git", ["status"], output: "")
        workspace.runner.on("git", ["rev-parse", "HEAD"], output: ReleaseFixtures.commit + "\n")
        workspace.runner.on("generate_keys", output: AppUpdateSettings.officialPublicKey + "\n")
        workspace.runner.on(
            "security", ["find-identity"],
            output: "  1) 0123 \"\(ReleaseFixtures.identity)\"\n     1 valid identities found\n")
        return workspace
    }

    static func inputs(version: String = "0.2.0", build: String = "3", minimum: String = "14.0") throws -> ReleaseInputs
    {
        try ReleaseInputs.parse(
            version: version, build: build, minimumMacOS: minimum, identity: ReleaseFixtures.identity,
            team: ReleaseFixtures.team, notaryProfile: "notary", keychain: nil)
    }

    static func preparer(_ workspace: ReleaseWorkspace, _ inputs: ReleaseInputs) throws -> ReleasePreparer {
        ReleasePreparer(environment: try workspace.environment(), inputs: inputs)
    }

    @Test("The source check reads the commit, the notes of the version, and the signed feed")
    func sourceFacts() async throws {
        let workspace = try Self.readyWorkspace()
        defer { workspace.remove() }
        let source = try await Self.preparer(workspace, Self.inputs()).checkSource()
        #expect(source.commit == ReleaseFixtures.commit)
        #expect(source.notes == "- New thing.\n")
    }

    @Test("Refuses a dirty worktree, another version, a minimum below the deployment target, and no notes")
    func sourceRefusals() async throws {
        let dirty = try Self.readyWorkspace()
        defer { dirty.remove() }
        dirty.runner.on("git", ["status"], output: "?? new-file\n")
        await #expect(throws: DevFailure.self) { _ = try await Self.preparer(dirty, Self.inputs()).checkSource() }
        let cases = [try Self.inputs(version: "0.3.0"), try Self.inputs(build: "4"), try Self.inputs(minimum: "13.5")]
        for inputs in cases {
            let workspace = try Self.readyWorkspace()
            defer { workspace.remove() }
            await #expect(throws: DevFailure.self) { _ = try await Self.preparer(workspace, inputs).checkSource() }
        }
        let noNotes = try Self.readyWorkspace()
        defer { noNotes.remove() }
        try noNotes.write(ReleaseWorkspace.changelog, to: "CHANGELOG.md")
        await #expect(throws: DevFailure.self) { _ = try await Self.preparer(noNotes, Self.inputs()).checkSource() }
    }

    @Test("The preflight checks the Keychain key, the notary profile, the identity, and the payloads")
    func preflight() async throws {
        let workspace = try Self.readyWorkspace()
        defer { workspace.remove() }
        try await ReleasePreflight(shell: workspace.shell(), inputs: Self.inputs()).run()
        let notary = try #require(workspace.runner.calls("xcrun", ["notarytool", "history"]).first)
        #expect(notary == ["notarytool", "history", "--keychain-profile", "notary", "--output-format", "json"])
        #expect(workspace.runner.calls("generate_keys") == [["--account", "dev.jerd.sparkle", "-p"]])
    }

    @Test("The preflight refuses another Sparkle key, a missing identity, and a missing payload")
    func preflightRefusals() async throws {
        let key = try Self.readyWorkspace()
        defer { key.remove() }
        key.runner.on("generate_keys", output: "AAAA\n")
        await #expect(throws: DevFailure.self) {
            try await ReleasePreflight(shell: key.shell(), inputs: Self.inputs()).run()
        }
        let identity = try Self.readyWorkspace()
        defer { identity.remove() }
        identity.runner.on("security", ["find-identity"], output: "     0 valid identities found\n")
        await #expect(throws: DevFailure.self) {
            try await ReleasePreflight(shell: identity.shell(), inputs: Self.inputs()).run()
        }
        let payload = try Self.readyWorkspace()
        defer { payload.remove() }
        try FileManager.default.removeItem(at: payload.path(".build/runtimes/payloads/mail"))
        await #expect(throws: DevFailure.self) {
            try await ReleasePreflight(shell: payload.shell(), inputs: Self.inputs()).run()
        }
    }

    @Test("A failed archive ends in the terminal prepareFailed state and keeps the log")
    func failureIsRecorded() async throws {
        let workspace = try Self.readyWorkspace()
        defer { workspace.remove() }
        workspace.runner.on("xcodebuild", ["archive"], status: 65, error: "error: signing failed")
        await #expect(throws: DevFailure.self) { try await Self.preparer(workspace, Self.inputs()).run() }
        let candidates = try CandidateStore(releases: workspace.repository.releases).candidates()
        let candidate = try #require(candidates.first)
        #expect(candidates.count == 1 && candidate.candidate.name.hasPrefix("Jerd-0.2.0-3-"))
        let state = try CandidateStore.load(candidate.layout)
        #expect(state.stage == .prepareFailed)
        #expect(state.failure?.contains("archive.log") == true)
        #expect(FileManager.default.fileExists(atPath: candidate.layout.log("archive").path))
        let attributes = try FileManager.default.attributesOfItem(atPath: candidate.layout.root.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(
            try Data(contentsOf: candidate.layout.notes)
                == Data("- New thing.\n\nRequires Apple Silicon and macOS 14.0 or later.\n".utf8))
    }
}
