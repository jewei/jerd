import Foundation
import JerdDatabases
import JerdFoundation
import JerdManifest
import JerdRuntimes
import JerdTestSupport
import JerdUI
import Testing

@testable import JerdLive

/// Pinned releases from memory, or a catalog that cannot be read, and an optional reusable payload.
struct FakeOnDemandReleases: OnDemandRuntimeProviding {
    var list: [RuntimeRelease] = []
    var failure: JerdError?
    var reusable: ReusablePayload?

    func releases() throws -> [RuntimeRelease] {
        if let failure { throw failure }
        return list
    }

    func reusablePayload(for kind: RuntimeKind, layout: DataLayout) async throws -> ReusablePayload? {
        reusable?.kind == kind ? reusable : nil
    }

    func hasReusablePayload(for kind: RuntimeKind, layout: DataLayout) async throws -> Bool {
        reusable?.kind == kind
    }
}

/// A volume with a fixed amount of free space, or one that cannot tell.
struct FakeFreeSpace: FreeSpaceReading {
    var bytes: Int64?

    func availableBytes(near url: URL) -> Int64? { bytes }
}

@Suite("Database runtimes on demand")
struct DatabaseRuntimeInstallerTests {
    static let postgresBuild = SettingsSamples.build(.postgresql, version: "2.9.6", digest: "9fc7")
    static let layout = DataLayout(root: URL(fileURLWithPath: "/nonexistent/Jerd"))

    static func pinned(
        _ kind: RuntimeKind, _ version: String, digest: String, link: String, size: Int64,
        engineVersion: String? = nil, installedSize: Int64? = nil
    ) -> RuntimeRelease {
        RuntimeRelease(
            kind: kind, version: version, artifact: .archive(URL(string: link)!, size: .exact(size)),
            archiveSHA256: digest, releasePage: URL(string: "https://github.com/PostgresApp/PostgresApp")!,
            engineVersion: engineVersion, installedSize: installedSize)
    }

    static let postgres = pinned(
        .postgresql, "2.9.6", digest: "9fc7",
        link: "https://github.com/PostgresApp/PostgresApp/releases/download/v2.9.6/Postgres-2.9.6-18.dmg",
        size: 122_517_005, installedSize: 750_547_900)

    private func installer(
        _ releases: FakeOnDemandReleases, installer: FakeManagedInstaller = FakeManagedInstaller(),
        manager: RecordingDatabaseManager = RecordingDatabaseManager(), free: Int64? = nil
    ) -> DatabaseRuntimeInstaller {
        DatabaseRuntimeInstaller(
            releases: releases, installer: installer, manager: manager, layout: Self.layout,
            freeSpace: FakeFreeSpace(bytes: free))
    }

    @Test("Offers map each pinned engine with its sizes, source, and engine version")
    func offersMapEachPinnedEngine() async {
        let engine = Self.pinned(
            .postgresql, "2.9.6", digest: "9fc7", link: Self.postgres.artifact.downloadURL!.absoluteString,
            size: 122_517_005, engineVersion: "18.6", installedSize: 750_547_900)
        #expect(
            await installer(FakeOnDemandReleases(list: [engine])).offers() == [
                DatabaseRuntimeOffer(
                    engine: .postgresql, versionLabel: "18.6", downloadSize: 122_517_005, source: "github.com",
                    installedSize: 750_547_900)
            ])
    }

    @Test("Other kinds and releases without an exact size are not offered")
    func otherKindsAreNotOffered() {
        let mail = Self.pinned(.mailpit, "1.31.3", digest: "f7", link: "https://github.com/a/b.tar.gz", size: 10)
        let limited = RuntimeRelease(
            kind: .postgresql, version: "2.9.6",
            artifact: .archive(Self.postgres.artifact.downloadURL!, size: .atMost(10)),
            archiveSHA256: "9fc7", releasePage: Self.postgres.releasePage)
        #expect(DatabaseRuntimeInstaller.offer(mail) == nil)
        #expect(DatabaseRuntimeInstaller.offer(limited) == nil)
    }

    @Test("A catalog that cannot be read offers nothing")
    func unreadableCatalogOffersNothing() async {
        let releases = FakeOnDemandReleases(failure: .unavailable("The app bundle has no runtimes.json."))
        #expect(await installer(releases).offers().isEmpty)
    }

    @Test("Install uses the pinned release, then registers the build under a new ID")
    func installRegistersTheBuild() async throws {
        let manager = RecordingDatabaseManager()
        let managed = FakeManagedInstaller([Self.postgresBuild])
        let runtime = try await installer(
            FakeOnDemandReleases(list: [Self.postgres]), installer: managed, manager: manager
        ).install(.postgresql) { _ in }
        #expect(runtime == (try RuntimeActivator.databaseRuntime(Self.postgresBuild)))
        #expect(await manager.registered == [[runtime]])
        // Database engines need no tools from other runtimes.
        #expect(await managed.tools.map(\.phpCLI) == [nil])
    }

    @Test("A verified payload of an earlier copy is registered again without a download")
    func reusesAnEarlierPayload() async throws {
        let folder = URL(fileURLWithPath: "/nonexistent/Jerd/database-runtimes/postgresql-18.6-universal")
        let earlier = ReusablePayload(
            id: "postgresql-18.6-universal", kind: .postgresql, version: "18.6", directory: folder)
        let manager = RecordingDatabaseManager()
        let managed = FakeManagedInstaller()
        let runtime = try await installer(
            FakeOnDemandReleases(list: [Self.postgres], reusable: earlier), installer: managed, manager: manager,
            free: 0
        ).install(.postgresql) { _ in }
        #expect(runtime == DatabaseRuntime(id: earlier.id, engine: .postgresql, version: "18.6", path: folder.path))
        #expect(await manager.registered == [[runtime]])
        #expect(await managed.tools.isEmpty)
    }

    @Test("Too little free space stops the installation before the download")
    func tooLittleFreeSpaceStopsTheInstallation() async {
        // No build of the pin is installed, so the install would download.
        let managed = FakeManagedInstaller()
        let manager = RecordingDatabaseManager()
        let installer = installer(
            FakeOnDemandReleases(list: [Self.postgres]), installer: managed, manager: manager, free: 100_000_000)
        await #expect {
            try await installer.install(.postgresql) { _ in }
        } throws: { error in
            let message = (error as? JerdError)?.message ?? ""
            return message.contains("873.1\u{00A0}MB") && message.contains("100\u{00A0}MB")
        }
        let registered = await manager.registered
        #expect(await managed.tools.isEmpty)
        #expect(registered.isEmpty)
    }

    @Test("Enough free space, or a volume that cannot tell, lets the installation run")
    func enoughOrUnknownFreeSpaceInstalls() async throws {
        for free in [Int64?.none, 2_000_000_000] {
            let managed = FakeManagedInstaller([Self.postgresBuild])
            _ = try await installer(FakeOnDemandReleases(list: [Self.postgres]), installer: managed, free: free)
                .install(.postgresql) { _ in }
            #expect(await managed.tools.count == 1)
        }
    }

    @Test("An engine without a pin installs nothing")
    func engineWithoutAPinInstallsNothing() async {
        let manager = RecordingDatabaseManager()
        let installer = installer(FakeOnDemandReleases(list: [Self.postgres]), manager: manager)
        await #expect(throws: JerdError.self) { try await installer.install(.mysql) { _ in } }
        #expect(await manager.registered.isEmpty)
    }

    @Test("A failed installation registers nothing")
    func failedInstallationRegistersNothing() async {
        let manager = RecordingDatabaseManager()
        // The fake has no build of the release, so its install stops.
        let installer = installer(FakeOnDemandReleases(list: [Self.postgres]), manager: manager)
        await #expect(throws: CancellationError.self) { try await installer.install(.postgresql) { _ in } }
        #expect(await manager.registered.isEmpty)
    }

    @Test("A port without on-demand installation offers nothing")
    func portWithoutOnDemandOffersNothing() async throws {
        let port = LiveDatabasesPort(
            manager: RecordingDatabaseManager(), runtimes: FakeServiceRuntimes(), layout: Self.layout.databases)
        #expect(await port.runtimeOffers().isEmpty)
        await #expect(throws: JerdError.self) { try await port.installRuntime(.postgresql) { _ in } }
    }

    @Test("The Runtimes snapshot lists the pinned on-demand releases")
    func runtimesSnapshotListsOnDemandReleases() async throws {
        let installer = FakeManagedInstaller()
        let owners = RecordingRuntimeOwners()
        let activator = RuntimeActivator(
            owners: owners, sites: RecordingSiteChanges(), inspector: FakeExecutableInspector())
        let inventory = LiveRuntimeInventory(
            catalog: installer, installer: installer, owners: owners, activator: activator,
            databases: self.installer(FakeOnDemandReleases(list: [Self.postgres]), installer: installer))
        #expect(try await inventory.snapshot().onDemand == [Self.postgres])
        #expect(try await inventory.snapshot().reusableOnDemand.isEmpty)
        let broken = LiveRuntimeInventory(
            catalog: installer, installer: installer, owners: owners, activator: activator,
            databases: self.installer(FakeOnDemandReleases(failure: .invalid("bad catalog")), installer: installer))
        #expect(try await broken.snapshot().onDemand.isEmpty)
    }

    @Test("An installed build of the pin skips the free-space check and is offered as a reuse")
    func installedBuildSkipsTheFreeSpaceCheck() async throws {
        let managed = FakeManagedInstaller([Self.postgresBuild])
        let installer = installer(FakeOnDemandReleases(list: [Self.postgres]), installer: managed, free: 1_000)
        #expect(await installer.offers().first?.reusesInstalledCopy == true)
        #expect(await installer.offers().first?.requiredSpace == 0)
        _ = try await installer.install(.postgresql) { _ in }
        #expect(await managed.tools.count == 1)
    }

    @Test("Runtimes › Install… of a pinned engine uses the one flow: reuse, free space, registration")
    func runtimesInstallUsesTheOneFlow() async throws {
        let folder = URL(fileURLWithPath: "/nonexistent/Jerd/database-runtimes/postgresql-18.6-universal")
        let earlier = ReusablePayload(
            id: "postgresql-18.6-universal", kind: .postgresql, version: "18.6", directory: folder)
        let managed = FakeManagedInstaller()
        let manager = RecordingDatabaseManager()
        let registered = DatabaseRuntime(id: earlier.id, engine: .postgresql, version: "18.6", path: folder.path)
        let owners = RecordingRuntimeOwners(records: RuntimeRecords(databases: [registered]))
        let inventory = LiveRuntimeInventory(
            catalog: managed, installer: managed, owners: owners,
            activator: RuntimeActivator(
                owners: owners, sites: RecordingSiteChanges(), inspector: FakeExecutableInspector()),
            databases: installer(
                FakeOnDemandReleases(list: [Self.postgres], reusable: earlier), installer: managed, manager: manager,
                free: 0))
        #expect(try await inventory.snapshot().reusableOnDemand == [.postgresql])
        let build = try await inventory.install(Self.postgres) { _ in }
        #expect(build.version == "18.6" && build.kind == .postgresql)
        #expect(await manager.registered == [[registered]])
        #expect(await managed.tools.isEmpty)
        // The flow registered the runtime; activation has nothing left to do.
        try await inventory.activate(build, useAsDefault: true)

        let tight = LiveRuntimeInventory(
            catalog: managed, installer: managed, owners: owners,
            activator: RuntimeActivator(
                owners: owners, sites: RecordingSiteChanges(), inspector: FakeExecutableInspector()),
            databases: installer(FakeOnDemandReleases(list: [Self.postgres]), installer: managed, free: 1_000))
        await #expect(throws: JerdError.self) { try await tight.install(Self.postgres) { _ in } }
        #expect(await managed.tools.isEmpty)
    }

    @Test("The live domain shares one installer between Runtimes and the Databases port")
    func liveDomainSharesOneInstaller() throws {
        let folder = try TemporaryDirectory("shared-installer")
        defer { folder.remove() }
        let domain = LiveDomain(
            configuration: LiveConfiguration(
                layout: folder.layout, appBundle: folder.url, resources: folder.url, appVersion: "test"))
        let port = LiveDatabasesPort(domain: domain)
        let inventory = LiveRuntimeInventory(domain: domain)
        let portInstaller = try #require(port.onDemand?.flow.installer as? RuntimeInstaller)
        let inventoryInstaller = try #require(inventory.installer as? RuntimeInstaller)
        #expect(portInstaller === domain.runtimeInstaller && inventoryInstaller === domain.runtimeInstaller)
    }
}
