import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@Suite struct OnDemandRuntimesTests {
    /// A bundle folder with only the committed catalog, as an app without database payloads has it.
    private func committedBundle(_ folder: TemporaryFolder) throws -> URL {
        let bundle = folder.path("RuntimePayloads")
        try OwnedDirectory.create(bundle)
        let catalog = try Data(contentsOf: Fixture.repositoryFile("Runtimes/runtimes.json"))
        try catalog.write(to: bundle.appendingPathComponent(RuntimePinCatalog.fileName))
        return bundle
    }

    private func committedPin(_ kind: RuntimeKind) throws -> RuntimePin {
        let data = try Data(contentsOf: Fixture.repositoryFile("Runtimes/runtimes.json"))
        return try #require(try RuntimePinCatalog.decode(data).pin(for: kind))
    }

    @Test func committedCatalogOffersExactlyTheThreeDatabasePins() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let releases = try OnDemandRuntimes(resources: try committedBundle(folder), architecture: .arm64).releases()
        #expect(releases.map(\.kind) == [.mysql, .postgresql])
        for release in releases {
            let pin = try committedPin(release.kind)
            let archive = try #require(pin.archive)
            #expect(release.artifact == .archive(archive.url, size: .exact(archive.size)))
            #expect(release.downloadSize == archive.size && release.archiveSHA256 == archive.sha256)
            #expect(release.version == pin.version && release.releasePage == pin.releasePage)
            #expect(release.pinnedSignature == pin.signature && release.signatureURL == pin.signature?.url)
            // The pinned sources pass the same release rules as every managed update.
            #expect(ReleasePolicy(platform: HostPlatform(architecture: .arm64, osMajor: 15)).check(release) == nil)
        }
        #expect(releases.first?.pinnedSignature != nil)
    }

    @Test func embeddedKindsAreNeverOfferedForDownload() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let source = OnDemandRuntimes(resources: try committedBundle(folder), architecture: .arm64)
        for kind in [RuntimeKind.php, .caddy, .composer, .laravel, .redis, .mailpit, .rustfs, .cloudflared] {
            #expect(try source.release(for: kind) == nil, "\(kind)")
        }
        #expect(try source.release(for: .mysql)?.versionLabel == "8.4.11")
        // The engine version of the pin, not the Postgres.app version, before the install.
        let postgres = try #require(try source.release(for: .postgresql))
        #expect(postgres.versionLabel == "18.6" && postgres.engineVersion == "18.6" && postgres.version == "2.9.6")
        #expect(postgres.title == "PostgreSQL 18.6")
    }

    @Test func catalogWithoutOnDemandPinsOffersNothing() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var builder = BundleBuilder(root: folder.path("bundle"))
        try builder.add(
            .redis, id: "redis-8.8.3-arm64", version: "8.8.3",
            files: [.init(path: "bin/redis-server", text: "r", executable: true)])
        try builder.writeCatalog()
        #expect(try OnDemandRuntimes(resources: folder.path("bundle"), architecture: .arm64).releases().isEmpty)
    }

    @Test func appWithoutACatalogCannotOfferRuntimes() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        #expect(throws: JerdError.self) {
            try OnDemandRuntimes(resources: folder.path("missing"), architecture: .arm64).releases()
        }
    }

    /// The pin of the builder is 10 bytes with the SHA-256 `digest("c")`.
    @Test(arguments: [5, 10])
    func downloadThatDoesNotMatchItsPinInstallsNothing(_ byteCount: Int) async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var builder = BundleBuilder(root: folder.path("bundle"))
        try builder.add(
            .mysql, id: "mysql-8.4.11-arm64", version: "8.4.11",
            files: [.init(path: "bin/mysqld", text: "m", executable: true)], embedded: false)
        try builder.writeCatalog()
        let release = try #require(
            try OnDemandRuntimes(resources: folder.path("bundle"), architecture: .arm64).release(for: .mysql))
        let url = try #require(release.artifact.downloadURL)
        let fetcher = FakeFetcher([url: Data(count: byteCount)])
        let commands = ScriptedCommandRunner()
        let installer = RuntimeInstaller(
            directory: folder.path("runtime-updates"), fetcher: fetcher, commands: commands,
            policy: ReleasePolicy(platform: HostPlatform(architecture: .arm64, osMajor: 15)))
        await #expect(throws: JerdError.self) { try await installer.install(release) }
        #expect(commands.requests.isEmpty)
        // The signature is never fetched: the size and the digest fail first.
        #expect(fetcher.requests == [url])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path("runtime-updates").path).isEmpty)
    }
}
