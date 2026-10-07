import Foundation
import JerdManifest
import Testing

@testable import JerdDevKit

@Suite("Release candidate files")
struct CandidateFilesTests {
    /// A candidate of 0.2.0 (3) with a disk image and a feed signed with the workspace key.
    static func candidate(_ workspace: ReleaseWorkspace) throws -> (layout: CandidateLayout, feed: Data) {
        let layout = CandidateLayout(
            releases: workspace.repository.releases, version: ReleaseVersion.release("0.2.0")!, build: 3)
        try FileManager.default.createDirectory(at: layout.root, withIntermediateDirectories: true)
        let image = Data("disk image".utf8)
        try image.write(to: layout.file("Jerd-0.2.0.dmg"))
        let source = try Data(contentsOf: workspace.path("appcast.xml"))
        try source.write(to: layout.sourceFeed)
        let item = AppcastWriter.Item(
            version: ReleaseVersion.release("0.2.0")!, build: 3, minimumMacOS: ReleaseVersion("14.0")!,
            notes: "- New thing.\n", publishedAt: Date(timeIntervalSince1970: 0), archiveLength: Int64(image.count),
            archiveSignature: try workspace.key.signature(of: image))
        let feed = try workspace.key.signedFeed(try AppcastWriter.feed(from: source, adding: item))
        try feed.write(to: layout.feed)
        return (layout, feed)
    }

    @Test("The candidate folder is named for the version and the build")
    func folderName() throws {
        let layout = CandidateLayout(
            releases: URL(filePath: "/r/.build/releases"), version: ReleaseVersion.release("0.2.0")!, build: 3)
        #expect(layout.root.path == "/r/.build/releases/Jerd-0.2.0-3")
    }

    @Test("A new run replaces an earlier candidate folder of the same version and build with a private one")
    func replacesFolder() throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        let layout = try Self.candidate(workspace).layout
        let builder = ReleaseBuilder(
            environment: try workspace.environment(), inputs: try ReleaseFixtures.inputs(),
            source: ReleaseSource(
                commit: ReleaseFixtures.commit, notes: "", feed: Data(), changelog: "",
                versionFile: XcconfigFile(path: "v", text: "")),
            layout: layout)
        try builder.makeFolder()
        #expect(try FileManager.default.contentsOfDirectory(atPath: layout.root.path).isEmpty)
        let attributes = try FileManager.default.attributesOfItem(atPath: layout.root.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test("The candidate feed passes with the public key and fails for a changed disk image or feed")
    func feedCheck() throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        let (layout, feed) = try Self.candidate(workspace)
        let check = CandidateFeedCheck(
            verifier: try workspace.key.verifier, version: ReleaseVersion.release("0.2.0")!, build: 3,
            minimumMacOS: ReleaseVersion("14.0")!)
        let image = layout.file("Jerd-0.2.0.dmg")
        try check.verify(feed: feed, diskImage: image)
        let other = CandidateFeedCheck(
            verifier: try TestFeedKey().verifier, version: check.version, build: 3, minimumMacOS: check.minimumMacOS)
        #expect(throws: DevFailure.self) { try other.verify(feed: feed, diskImage: image) }
        let wrongBuild = CandidateFeedCheck(
            verifier: check.verifier, version: check.version, build: 4, minimumMacOS: check.minimumMacOS)
        #expect(throws: DevFailure.self) { try wrongBuild.verify(feed: feed, diskImage: image) }
        try Data("changed image".utf8).write(to: image)
        #expect(throws: DevFailure.self) { try check.verify(feed: feed, diskImage: image) }
    }

    @Test("The feed signer signs the disk image and the feed with the Keychain account and checks both")
    func feedSigner() async throws {
        let workspace = try ReleaseWorkspace()
        defer { workspace.remove() }
        let layout = try Self.candidate(workspace).layout
        let image = layout.file("Jerd-0.2.0.dmg")
        let key = workspace.key
        let signature = try key.signature(of: Data(contentsOf: image))
        workspace.runner.on("sign_update", ["--account", "dev.jerd.sparkle", "-p"], output: signature + "\n")
        let feed = layout.feed
        workspace.runner.on(
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
        try await FeedSigner(shell: workspace.shell(), layout: layout).run(item: item, diskImage: image, check: check)
        #expect(workspace.runner.calls("sign_update").count == 2)
    }

    @Test("The release commit files keep the rest of the version file and keep an empty unreleased section")
    func commitFiles() throws {
        let source = ReleaseSource(
            commit: ReleaseFixtures.commit, notes: "- New thing.\n", feed: Data(),
            changelog: ReleaseWorkspace.changelog,
            versionFile: XcconfigFile(
                path: "Configuration/Version.xcconfig",
                text: "// The app version.\nMARKETING_VERSION = 0.1.0\nCURRENT_PROJECT_VERSION = 2\n"))
        let files = try ReleaseCommitFiles(
            source: source, feed: Data("feed".utf8), version: ReleaseVersion.release("0.2.0")!, build: 3,
            date: FixedReleaseClock().now())
        #expect(files.versionFile == "// The app version.\nMARKETING_VERSION = 0.2.0\nCURRENT_PROJECT_VERSION = 3\n")
        #expect(files.changelog.contains("## [Unreleased]\n\n## [0.2.0] - 2026-10-06\n\n- New thing."))
        #expect(ReleaseNotes.unreleased(in: files.changelog) == "")
        #expect(files.feed == Data("feed".utf8))
    }
}
