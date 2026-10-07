import Foundation
import Testing

@testable import JerdDevKit

@Suite("Release candidate files")
struct CandidateFilesTests {
    @Test("Clean removes old finished candidates and keeps started publications")
    func cleans() throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        let store = CandidateStore(releases: workspace.repository.releases)
        var layouts: [CandidateLayout] = []
        for (index, stage) in [ReleaseStage.published, .prepareFailed, .draftCreated, .prepared].enumerated() {
            let layout = try store.create(version: ReleaseVersion.release("0.2.0")!, build: index + 3)
            var state = ReleaseState(startedAt: Date(timeIntervalSince1970: Double(index) * 100))
            if stage == .prepareFailed {
                try state.advance(to: .prepareFailed, at: Date())
            }
            for next in ReleaseStage.allCases where next != .preparing && next != .prepareFailed {
                guard state.stage != stage else { break }
                try state.advance(to: next, at: Date())
            }
            try CandidateStore.save(state, to: layout)
            layouts.append(layout)
        }
        let removed = try CandidateCleaner(environment: workspace.environment()).run(keep: 1)
        #expect(removed.count == 2)
        let exists = layouts.map { FileManager.default.fileExists(atPath: $0.root.path) }
        #expect(exists == [false, false, true, true])
        #expect(workspace.output.all.contains("Kept"))
    }

    @Test("A candidate folder must hold a state file")
    func existingNeedsState() throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        #expect(throws: DevFailure.self) { try CandidateStore.existing("nope", workingDirectory: workspace.root) }
    }

    @Test("Validation compares every listed file with its digest and refuses unsafe names")
    func checksFiles() throws {
        let fixture = try PublicationFixture()
        defer { fixture.remove() }
        let manifest = try ReleaseManifest.decode(Data(contentsOf: fixture.layout.manifest))
        try ReleaseValidator.checkFiles(manifest, in: fixture.layout.root)
        try Data("other".utf8).write(to: fixture.layout.file("Jerd-0.2.0-3.dSYMs.zip"))
        #expect(throws: DevFailure.self) { try ReleaseValidator.checkFiles(manifest, in: fixture.layout.root) }
        var unsafe = manifest
        unsafe.files["../appcast.xml"] = unsafe.files["appcast.xml"]
        #expect(throws: DevFailure.self) { try ReleaseValidator.checkFiles(unsafe, in: fixture.layout.root) }
    }

    @Test("The candidate feed passes with the public key and fails for a changed disk image or feed")
    func feedCheck() throws {
        let fixture = try PublicationFixture()
        defer { fixture.remove() }
        let check = CandidateFeedCheck(
            verifier: try fixture.workspace.key.verifier, version: ReleaseVersion.release("0.2.0")!, build: 3,
            minimumMacOS: ReleaseVersion("14.0")!)
        let image = fixture.layout.file("Jerd-0.2.0.dmg")
        try check.verify(feed: fixture.candidateFeed, diskImage: image)
        var other = check
        other = CandidateFeedCheck(
            verifier: try TestFeedKey().verifier, version: check.version, build: 3, minimumMacOS: check.minimumMacOS)
        #expect(throws: DevFailure.self) { try other.verify(feed: fixture.candidateFeed, diskImage: image) }
        let wrongBuild = CandidateFeedCheck(
            verifier: check.verifier, version: check.version, build: 4, minimumMacOS: check.minimumMacOS)
        #expect(throws: DevFailure.self) { try wrongBuild.verify(feed: fixture.candidateFeed, diskImage: image) }
        try Data("changed image".utf8).write(to: image)
        #expect(throws: DevFailure.self) { try check.verify(feed: fixture.candidateFeed, diskImage: image) }
    }

    @Test("The feed signer signs the disk image and the feed with the Keychain account and checks both")
    func feedSigner() async throws {
        let fixture = try PublicationFixture()
        defer { fixture.remove() }
        let image = fixture.layout.file("Jerd-0.2.0.dmg")
        let key = fixture.workspace.key
        let signature = try key.signature(of: Data(contentsOf: image))
        fixture.runner.on("sign_update", ["--account", "dev.jerd.sparkle", "-p"], output: signature + "\n")
        let feed = fixture.layout.feed
        fixture.runner.on(
            "sign_update", ["--account", "dev.jerd.sparkle", feed.path],
            effect: { _ in
                let content = try Data(contentsOf: feed)
                try key.signedFeed(content).write(to: feed)
            })
        let item = AppcastWriter.Item(
            version: ReleaseVersion.release("0.2.0")!, build: 3, minimumMacOS: ReleaseVersion("14.0")!,
            notes: "- New thing.\n", publishedAt: Date(), archiveLength: 10, archiveSignature: "")
        let check = CandidateFeedCheck(
            verifier: try key.verifier, version: item.version, build: 3, minimumMacOS: item.minimumMacOS)
        try await FeedSigner(shell: fixture.workspace.shell(), layout: fixture.layout).run(
            item: item, diskImage: image, check: check)
        #expect(fixture.runner.calls("sign_update").count == 2)
    }

    @Test("Runtime tests get receipt paths, the switches of all groups, and no inherited JERD values")
    func runtimeTestEnvironment() throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        let layout = CandidateLayout(root: workspace.path("candidate"))
        try PayloadFixture.write(to: layout.appPayloads)
        let environment = try ReleaseRuntimeTests(shell: workspace.shell(), layout: layout).environment()
        #expect(environment["JERD_PHP_CLI"]?.hasSuffix("/development/php-8.5.11-arm64/bin/tool") == true)
        #expect(environment["JERD_PHP_FPM"]?.hasSuffix("/bin/php-fpm") == true)
        #expect(environment["JERD_STORAGE_INTEGRATION"] == "1" && environment["JERD_DATABASE_INTEGRATION"] == "1")
        #expect(environment["JERD_DATABASE_RUNTIMES"] == layout.integration.appending(path: "database").path)
        #expect(environment["PATH"] == "/usr/bin")
    }

    @Test("Status shows the stage, the history, and the next action")
    func status() throws {
        var state = ReleaseState(startedAt: Date(timeIntervalSince1970: 0))
        try state.advance(to: .prepared, at: Date(timeIntervalSince1970: 60))
        let lines = CandidateStatus.lines(state, manifest: ReleaseStateTests.manifest())
        #expect(lines.first == "Release 0.2.0 (3) from aaaaaaaaaaaa.")
        #expect(lines.contains("Stage: prepared."))
        #expect(lines.last == "Next: Run ./dev release publish with this folder.")
    }
}
