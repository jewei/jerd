import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import JerdStorage
import JerdTestSupport
import JerdUI
import Testing

@testable import JerdLive

/// The XZ library of a bundle in memory, or a bundle without it.
struct FakeLZMA: LZMAProviding {
    var library: SupportLibrary?

    func bundledLZMA() async throws -> SupportLibrary? { library }
}

@Suite("RustFS on demand")
struct StorageRuntimeInstallerTests {
    static let layout = DataLayout(root: URL(fileURLWithPath: "/nonexistent/Jerd"))
    static let lzma = SupportLibrary(
        library: URL(
            fileURLWithPath: "/Applications/Jerd.app/Contents/Resources/RuntimePayloads/support/xz/liblzma.5.dylib"),
        license: URL(
            fileURLWithPath: "/Applications/Jerd.app/Contents/Resources/RuntimePayloads/support/xz/XZ-LICENSE.txt"))
    static let rustfs = DatabaseRuntimeInstallerTests.pinned(
        .rustfs, "1.0.0", digest: "06e3",
        link: "https://github.com/rustfs/rustfs/releases/download/1.0.0/rustfs-macos-aarch64-v1.0.0.zip",
        size: 87_018_416, installedSize: 223_534_901)
    static let rustfsBuild = SettingsSamples.build(.rustfs, version: "1.0.0", digest: "06e3")
    static let earlier = ReusablePayload(
        id: "rustfs-1.0.0-arm64-0123456789abcdef", kind: .rustfs, version: "1.0.0",
        directory: URL(fileURLWithPath: "/nonexistent/Jerd/storage-runtimes/rustfs-1.0.0-arm64-0123456789abcdef"))

    private func installer(
        _ releases: FakeOnDemandReleases = FakeOnDemandReleases(list: [Self.rustfs]),
        installer: FakeManagedInstaller = FakeManagedInstaller(),
        manager: RecordingStorageManager = RecordingStorageManager(), lzma: SupportLibrary? = Self.lzma,
        free: Int64? = nil
    ) -> StorageRuntimeInstaller {
        StorageRuntimeInstaller(
            flow: OnDemandInstallFlow(
                releases: releases, installer: installer, layout: Self.layout, freeSpace: FakeFreeSpace(bytes: free)),
            manager: manager, lzma: FakeLZMA(library: lzma))
    }

    @Test("The offer names the pinned version, the sizes, and the source")
    func offerMapsThePin() async {
        #expect(
            await installer().offer()
                == StorageRuntimeOffer(
                    versionLabel: "1.0.0", downloadSize: 87_018_416, source: "github.com", installedSize: 223_534_901))
        #expect(await installer().offer()?.requiredSpace == 87_018_416 + 223_534_901)
    }

    @Test("Another kind, an inexact size, no pin, or a bad catalog offers nothing")
    func otherReleasesOfferNothing() async {
        let mail = DatabaseRuntimeInstallerTests.pinned(
            .mailpit, "1.31.3", digest: "f7", link: "https://github.com/a/b.tar.gz", size: 10)
        let limited = RuntimeRelease(
            kind: .rustfs, version: "1.0.0", artifact: .archive(Self.rustfs.artifact.downloadURL!, size: .atMost(10)),
            archiveSHA256: "06e3", releasePage: Self.rustfs.releasePage)
        #expect(StorageRuntimeInstaller.offer(mail) == nil)
        #expect(StorageRuntimeInstaller.offer(limited) == nil)
        #expect(await installer(FakeOnDemandReleases(list: [mail])).offer() == nil)
        #expect(await installer(FakeOnDemandReleases(failure: .invalid("bad catalog"))).offer() == nil)
    }

    @Test("Install builds the pin with the app's XZ library, then registers it under a new ID")
    func installUsesTheAppLibraryAndRegisters() async throws {
        let manager = RecordingStorageManager()
        let managed = FakeManagedInstaller([Self.rustfsBuild])
        let runtime = try await installer(installer: managed, manager: manager).install { _ in }
        #expect(runtime == RuntimeActivator.storageRuntime(Self.rustfsBuild))
        #expect(await managed.tools.map(\.lzma) == [Self.lzma])
        // Only the runtime record changes: no bucket, start, or credential call.
        #expect(await manager.calls == ["register \(runtime.id)"])
    }

    @Test("Without the XZ library the install stops before any download and registers nothing")
    func missingLibraryStopsBeforeTheDownload() async {
        let manager = RecordingStorageManager()
        let managed = FakeManagedInstaller()
        await #expect {
            try await installer(installer: managed, manager: manager, lzma: nil).install { _ in }
        } throws: { error in
            (error as? JerdError)?.message.contains("no XZ library") == true
        }
        #expect(await managed.tools.isEmpty)
        #expect(await manager.calls.isEmpty)
    }

    @Test("A verified RustFS of an earlier copy is registered again; nothing is downloaded")
    func reusesAnEarlierPayload() async throws {
        let manager = RecordingStorageManager()
        let managed = FakeManagedInstaller()
        let releases = FakeOnDemandReleases(list: [Self.rustfs], reusable: Self.earlier)
        let installer = installer(releases, installer: managed, manager: manager, lzma: nil, free: 0)
        #expect(await installer.offer()?.reusesInstalledCopy == true)
        #expect(await installer.offer()?.requiredSpace == 0)
        let messages = ProgressLog()
        let runtime = try await installer.install { messages.append($0.message) }
        #expect(
            runtime
                == StorageRuntime(id: Self.earlier.id, version: "1.0.0", path: Self.earlier.directory.path))
        #expect(messages.all == ["Using the RustFS 1.0.0 that is already on this Mac."])
        #expect(await managed.tools.isEmpty)
        #expect(await manager.calls == ["register \(runtime.id)"])
    }

    @Test("Too little free space stops the install before the download")
    func tooLittleFreeSpaceStops() async {
        let managed = FakeManagedInstaller()
        let manager = RecordingStorageManager()
        await #expect {
            try await installer(installer: managed, manager: manager, free: 100_000_000).install { _ in }
        } throws: { error in
            (error as? JerdError)?.message.contains("310.6\u{00A0}MB") == true
        }
        #expect(await managed.tools.isEmpty)
        #expect(await manager.calls.isEmpty)
    }

    @Test("A failed or cancelled build registers nothing")
    func failedBuildRegistersNothing() async {
        let manager = RecordingStorageManager()
        // The fake has no build of the release, so its install stops as a cancel does.
        await #expect(throws: CancellationError.self) { try await installer(manager: manager).install { _ in } }
        #expect(await manager.calls.isEmpty)
        let none = installer(FakeOnDemandReleases(list: []), manager: manager)
        await #expect(throws: JerdError.self) { try await none.install { _ in } }
    }

    @Test("Runtimes › Install… of RustFS uses the same flow, and activation has nothing left to do")
    func runtimesInstallUsesTheOneFlow() async throws {
        let managed = FakeManagedInstaller()
        let manager = RecordingStorageManager()
        let registered = StorageRuntime(id: Self.earlier.id, version: "1.0.0", path: Self.earlier.directory.path)
        let owners = RecordingRuntimeOwners(records: RuntimeRecords(storage: registered))
        let inventory = LiveRuntimeInventory(
            catalog: managed, installer: managed, owners: owners,
            activator: RuntimeActivator(
                owners: owners, sites: RecordingSiteChanges(), inspector: FakeExecutableInspector()),
            storage: installer(
                FakeOnDemandReleases(list: [Self.rustfs], reusable: Self.earlier), installer: managed,
                manager: manager, free: 0))
        let snapshot = try await inventory.snapshot()
        #expect(snapshot.onDemand == [Self.rustfs] && snapshot.reusableOnDemand == [.rustfs])
        let build = try await inventory.install(Self.rustfs) { _ in }
        #expect(build.kind == .rustfs && build.version == "1.0.0")
        #expect(await manager.calls == ["register \(registered.id)"])
        #expect(await managed.tools.isEmpty)
        try await inventory.activate(build, useAsDefault: true)
        #expect(await owners.calls.isEmpty)
    }

    @Test("The live Storage port shares the one installer and the XZ library of the bootstrap")
    func liveDomainSharesOneInstaller() throws {
        let folder = try TemporaryDirectory("storage-installer")
        defer { folder.remove() }
        let domain = LiveDomain(
            configuration: LiveConfiguration(
                layout: folder.layout, appBundle: folder.url, resources: folder.url, appVersion: "test"))
        let port = LiveStoragePort(domain: domain)
        let inventory = LiveRuntimeInventory(domain: domain)
        let portInstaller = try #require(port.onDemand?.flow.installer as? RuntimeInstaller)
        let inventoryInstaller = try #require(inventory.storage?.flow.installer as? RuntimeInstaller)
        #expect(portInstaller === domain.runtimeInstaller && inventoryInstaller === domain.runtimeInstaller)
        #expect((port.onDemand?.lzma as? BundledRuntimeBootstrap) === domain.bootstrap)
    }
}
