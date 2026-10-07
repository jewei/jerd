import Foundation
import JerdDatabases
import JerdFoundation
import JerdManifest
import JerdRuntimes
import JerdUI
import Testing

@testable import JerdLive

/// Pinned releases from memory, or a catalog that cannot be read.
struct FakeOnDemandReleases: OnDemandRuntimeProviding {
    var list: [RuntimeRelease] = []
    var failure: JerdError?

    func releases() throws -> [RuntimeRelease] {
        if let failure { throw failure }
        return list
    }
}

@Suite("Database runtimes on demand")
struct DatabaseRuntimeInstallerTests {
    static let redisBuild = SettingsSamples.build(.redis, version: "8.8.3", digest: "13db")

    static func pinned(
        _ kind: RuntimeKind, _ version: String, digest: String, link: String, size: Int64,
        engineVersion: String? = nil
    ) -> RuntimeRelease {
        RuntimeRelease(
            kind: kind, version: version, artifact: .archive(URL(string: link)!, size: .exact(size)),
            archiveSHA256: digest, releasePage: URL(string: "https://download.redis.io/")!,
            engineVersion: engineVersion)
    }

    static let redis = pinned(
        .redis, "8.8.3", digest: "13db", link: "https://download.redis.io/releases/redis-8.8.3.tar.gz", size: 4_496_813)
    static let postgres = pinned(
        .postgresql, "2.9.6", digest: "9fc7",
        link: "https://github.com/PostgresApp/PostgresApp/releases/download/v2.9.6/Postgres-2.9.6-18.dmg",
        size: 122_517_005, engineVersion: "18.6")

    @Test func offersMapEachPinnedEngineWithItsSizeAndSource() {
        let installer = DatabaseRuntimeInstaller(
            releases: FakeOnDemandReleases(list: [Self.redis, Self.postgres]), installer: FakeManagedInstaller(),
            manager: RecordingDatabaseManager())
        #expect(
            installer.offers() == [
                DatabaseRuntimeOffer(
                    engine: .redis, versionLabel: "8.8.3", downloadSize: 4_496_813, source: "download.redis.io"),
                DatabaseRuntimeOffer(
                    engine: .postgresql, versionLabel: "18.6", downloadSize: 122_517_005,
                    source: "github.com"),
            ])
    }

    @Test func otherKindsAndReleasesWithoutAnExactSizeAreNotOffered() {
        let mail = Self.pinned(.mailpit, "1.31.3", digest: "f7", link: "https://github.com/a/b.tar.gz", size: 10)
        var limited = Self.redis
        limited = RuntimeRelease(
            kind: .redis, version: "8.8.3", artifact: .archive(limited.artifact.downloadURL!, size: .atMost(10)),
            archiveSHA256: "13db", releasePage: limited.releasePage)
        #expect(DatabaseRuntimeInstaller.offer(mail) == nil)
        #expect(DatabaseRuntimeInstaller.offer(limited) == nil)
    }

    @Test func aCatalogThatCannotBeReadOffersNothing() {
        let installer = DatabaseRuntimeInstaller(
            releases: FakeOnDemandReleases(failure: .unavailable("The app bundle has no runtimes.json.")),
            installer: FakeManagedInstaller(), manager: RecordingDatabaseManager())
        #expect(installer.offers().isEmpty)
    }

    @Test func installUsesThePinnedReleaseThenRegistersTheBuildUnderANewID() async throws {
        let manager = RecordingDatabaseManager()
        let managed = FakeManagedInstaller([Self.redisBuild])
        let installer = DatabaseRuntimeInstaller(
            releases: FakeOnDemandReleases(list: [Self.postgres, Self.redis]), installer: managed, manager: manager)
        let runtime = try await installer.install(.redis) { _ in }
        #expect(runtime == (try RuntimeActivator.databaseRuntime(Self.redisBuild)))
        #expect(runtime.id == Self.redisBuild.folderName && runtime.path == Self.redisBuild.directory.path)
        #expect(await manager.registered == [[runtime]])
        // Database engines need no tools from other runtimes.
        #expect(await managed.tools.map(\.phpCLI) == [nil])
    }

    @Test func anEngineWithoutAPinInstallsNothing() async {
        let manager = RecordingDatabaseManager()
        let installer = DatabaseRuntimeInstaller(
            releases: FakeOnDemandReleases(list: [Self.redis]), installer: FakeManagedInstaller(), manager: manager)
        await #expect(throws: JerdError.self) { try await installer.install(.mysql) { _ in } }
        #expect(await manager.registered.isEmpty)
    }

    @Test func aFailedInstallationRegistersNothing() async {
        let manager = RecordingDatabaseManager()
        // The fake has no build of the release, so its install stops.
        let installer = DatabaseRuntimeInstaller(
            releases: FakeOnDemandReleases(list: [Self.redis]), installer: FakeManagedInstaller(), manager: manager)
        await #expect(throws: CancellationError.self) { try await installer.install(.redis) { _ in } }
        #expect(await manager.registered.isEmpty)
    }

    @Test func aPortWithoutOnDemandInstallationOffersNothing() async throws {
        let port = LiveDatabasesPort(
            manager: RecordingDatabaseManager(), runtimes: FakeServiceRuntimes(),
            layout: DataLayout(root: URL(fileURLWithPath: "/nonexistent")).databases)
        #expect(await port.runtimeOffers().isEmpty)
        await #expect(throws: JerdError.self) { try await port.installRuntime(.redis) { _ in } }
    }

    @Test func theRuntimesSnapshotListsThePinnedOnDemandReleases() async throws {
        let installer = FakeManagedInstaller()
        let owners = RecordingRuntimeOwners()
        let inventory = LiveRuntimeInventory(
            catalog: installer, installer: installer, owners: owners,
            activator: RuntimeActivator(
                owners: owners, sites: RecordingSiteChanges(), inspector: FakeExecutableInspector()),
            onDemand: FakeOnDemandReleases(list: [Self.redis]))
        #expect(try await inventory.snapshot().onDemand == [Self.redis])
        let broken = LiveRuntimeInventory(
            catalog: installer, installer: installer, owners: owners,
            activator: RuntimeActivator(
                owners: owners, sites: RecordingSiteChanges(), inspector: FakeExecutableInspector()),
            onDemand: FakeOnDemandReleases(failure: .invalid("bad catalog")))
        #expect(try await broken.snapshot().onDemand.isEmpty)
    }
}
