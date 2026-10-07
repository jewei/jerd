import Foundation
import JerdDatabases
import JerdFoundation
import JerdMail
import JerdStorage
import JerdTestSupport
import Testing

@testable import JerdLive

@Suite("Live service ports")
struct LiveServicePortsTests {
    static let corrupt = JerdError.corrupt("The settings are corrupt.")

    // MARK: Databases

    @Test func databaseLoadInstallsOnlyTheEnginesWithoutARuntime() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let manager = RecordingDatabaseManager(DatabaseConfiguration(runtimes: [FakeServiceRuntimes.mysql]))
        let runtimes = FakeServiceRuntimes()
        let port = LiveDatabasesPort(manager: manager, runtimes: runtimes, layout: temporary.layout.databases)

        let snapshot = try await port.load()

        #expect(await runtimes.databaseRequests == [[.mysql]])
        #expect(await manager.registered == [[FakeServiceRuntimes.redis]])
        #expect(snapshot.configuration.runtimes == [FakeServiceRuntimes.mysql, FakeServiceRuntimes.redis])
    }

    @Test func databaseLoadInstallsNothingWhenEveryEngineHasARuntime() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let postgres = DatabaseRuntime(id: "pg", engine: .postgresql, version: "18.6", path: "/runtimes/pg")
        let manager = RecordingDatabaseManager(
            DatabaseConfiguration(runtimes: [FakeServiceRuntimes.mysql, postgres, FakeServiceRuntimes.redis]))
        let runtimes = FakeServiceRuntimes()

        _ = try await LiveDatabasesPort(manager: manager, runtimes: runtimes, layout: temporary.layout.databases)
            .load()

        #expect(await runtimes.databaseRequests.isEmpty)
    }

    @Test func corruptDatabaseSettingsFailTheLoadBeforeAnyInstall() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let manager = RecordingDatabaseManager(loadFailure: Self.corrupt)
        let runtimes = FakeServiceRuntimes()
        let port = LiveDatabasesPort(manager: manager, runtimes: runtimes, layout: temporary.layout.databases)

        await #expect(throws: Self.corrupt) { try await port.load() }
        #expect(await runtimes.databaseRequests.isEmpty)
    }

    @Test func aFailedBundledDatabaseSetupKeepsTheLoadUsable() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let manager = RecordingDatabaseManager()
        let port = LiveDatabasesPort(
            manager: manager, runtimes: FakeServiceRuntimes(failure: .unavailable("No payloads.")),
            layout: temporary.layout.databases)

        let snapshot = try await port.load()

        #expect(snapshot.configuration.runtimes.isEmpty)
        #expect(await manager.registered.isEmpty)
    }

    @Test func databaseStopAllFailureReachesTheQuit() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let manager = RecordingDatabaseManager()
        await manager.failStopAll(.timedOut("MySQL did not stop."))
        let port = LiveDatabasesPort(
            manager: manager, runtimes: FakeServiceRuntimes(), layout: temporary.layout.databases)

        await #expect(throws: JerdError.timedOut("MySQL did not stop.")) { try await port.stopAll() }
    }

    @Test func databaseFilesFollowTheInstanceLayout() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let layout = temporary.layout.databases
        let id = UUID()
        let port = LiveDatabasesPort(
            manager: RecordingDatabaseManager(), runtimes: FakeServiceRuntimes(), layout: layout)
        #expect(await port.files(for: id).hasDataFolder == false)

        try FileManager.default.createDirectory(
            at: layout.instance(id).dataDirectory, withIntermediateDirectories: true)
        let files = await port.files(for: id)

        #expect(files.dataFolder == layout.instance(id).dataDirectory)
        #expect(files.log == layout.instance(id).logFile)
        #expect(files.hasDataFolder)
        #expect(!files.hasLog)
    }

    // MARK: Mail

    @Test func mailLoadInstallsMailpitOnlyWhenNoRuntimeIsSaved() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let manager = RecordingMailManager()
        let runtimes = FakeServiceRuntimes()
        let port = LiveMailPort(manager: manager, runtimes: runtimes, layout: temporary.layout.mail)

        let snapshot = try await port.load()
        _ = try await port.load()

        #expect(snapshot.settings.runtime == FakeServiceRuntimes.mail)
        #expect(await runtimes.mailRequests == 1)
    }

    @Test func corruptMailSettingsFailTheLoadBeforeAnyInstall() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let runtimes = FakeServiceRuntimes()
        let port = LiveMailPort(
            manager: RecordingMailManager(loadFailure: Self.corrupt), runtimes: runtimes,
            layout: temporary.layout.mail)

        await #expect(throws: Self.corrupt) { try await port.load() }
        #expect(await runtimes.mailRequests == 0)
    }

    @Test func aFailedMailpitSetupKeepsTheLoadUsable() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let port = LiveMailPort(
            manager: RecordingMailManager(), runtimes: FakeServiceRuntimes(failure: .unavailable("No payloads.")),
            layout: temporary.layout.mail)

        #expect(try await port.load().settings.runtime == nil)
    }

    @Test func mailFilesAreTheInboxAndTheServerLog() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let layout = temporary.layout.mail
        let files = await LiveMailPort(manager: RecordingMailManager(), runtimes: FakeServiceRuntimes(), layout: layout)
            .files()

        #expect(files.dataFolder == layout.inboxDirectory)
        #expect(files.log == layout.logFile)
    }

    // MARK: Storage

    @Test func storageLoadInstallsRustFSOnlyWhenNoRuntimeIsSaved() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let manager = RecordingStorageManager()
        let runtimes = FakeServiceRuntimes()
        let port = LiveStoragePort(manager: manager, runtimes: runtimes, layout: temporary.layout.storage)

        let snapshot = try await port.load()
        _ = try await port.load()

        #expect(snapshot.settings.runtime == FakeServiceRuntimes.storage)
        #expect(await runtimes.storageRequests == 1)
    }

    @Test func storageLoadOfAnAppWithoutRustFSRegistersNothingAndReportsNoFailure() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let manager = RecordingStorageManager()
        let runtimes = FakeServiceRuntimes(embedsStorage: false)
        let port = LiveStoragePort(manager: manager, runtimes: runtimes, layout: temporary.layout.storage)

        #expect(try await port.load().settings.runtime == nil)
        #expect(await port.runtimeSetupFailure() == nil)
        #expect(await manager.calls == ["load"])
        // A port without on-demand installation offers nothing and installs nothing.
        #expect(await port.runtimeOffer() == nil)
        await #expect(throws: JerdError.self) { try await port.installRuntime { _ in } }
    }

    @Test func storageThatAnEarlierCopyRegisteredKeepsItsRuntime() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        var settings = StorageSettings()
        settings.runtime = StorageRuntime(
            id: "rustfs-1.0.0-arm64-0123456789abcdef", version: "1.0.0",
            path: temporary.path("storage-runtimes/rustfs-1.0.0-arm64-0123456789abcdef").path)
        let manager = RecordingStorageManager(settings)
        let runtimes = FakeServiceRuntimes(embedsStorage: false)
        let port = LiveStoragePort(manager: manager, runtimes: runtimes, layout: temporary.layout.storage)

        #expect(try await port.load().settings.runtime == settings.runtime)
        #expect(await runtimes.storageRequests == 0)
        #expect(await manager.calls == ["load"])
    }

    @Test func storagePortInstallsThroughTheOnDemandFlow() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let manager = RecordingStorageManager()
        let managed = FakeManagedInstaller([StorageRuntimeInstallerTests.rustfsBuild])
        let onDemand = StorageRuntimeInstaller(
            flow: OnDemandInstallFlow(
                releases: FakeOnDemandReleases(list: [StorageRuntimeInstallerTests.rustfs]), installer: managed,
                layout: temporary.layout, freeSpace: FakeFreeSpace(bytes: nil)),
            manager: manager, lzma: FakeLZMA(library: StorageRuntimeInstallerTests.lzma))
        let port = LiveStoragePort(
            manager: manager, runtimes: FakeServiceRuntimes(embedsStorage: false), layout: temporary.layout.storage,
            onDemand: onDemand)

        _ = try await port.load()
        // The build exists already, so the offer says that nothing is downloaded.
        #expect(await port.runtimeOffer()?.reusesInstalledCopy == true)
        let runtime = try await port.installRuntime { _ in }
        #expect(await port.snapshot().settings.runtime == runtime)
        #expect(await manager.calls == ["load", "register \(runtime.id)"])
    }

    @Test func corruptStorageSettingsFailTheLoadBeforeAnyInstall() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let runtimes = FakeServiceRuntimes()
        let port = LiveStoragePort(
            manager: RecordingStorageManager(loadFailure: Self.corrupt), runtimes: runtimes,
            layout: temporary.layout.storage)

        await #expect(throws: Self.corrupt) { try await port.load() }
        #expect(await runtimes.storageRequests == 0)
    }

    @Test func storageForwardsBucketWorkUnchanged() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let manager = RecordingStorageManager()
        let port = LiveStoragePort(
            manager: manager, runtimes: FakeServiceRuntimes(), layout: temporary.layout.storage)

        try await port.addBucket(name: "uploads", publicRead: false)
        try await port.retryBucket("uploads")
        try await port.refreshBuckets()

        #expect(await manager.calls == ["addBucket uploads false", "retryBucket uploads", "refreshBuckets"])
    }

    @Test func storageFilesAreTheDataFolderAndTheServerLog() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let layout = temporary.layout.storage
        let files = await LiveStoragePort(
            manager: RecordingStorageManager(), runtimes: FakeServiceRuntimes(), layout: layout
        ).files()

        #expect(files.dataFolder == layout.dataDirectory)
        #expect(files.log == layout.logFile)
    }

    // MARK: Launch

    /// A launch loads services and installs runtimes, but never starts one.
    @Test func loadsInstallRuntimesButNeverStartAService() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let layout = temporary.layout
        let databases = RecordingDatabaseManager()
        let mail = RecordingMailManager()
        let storage = RecordingStorageManager()
        let runtimes = FakeServiceRuntimes()

        _ = try await LiveDatabasesPort(manager: databases, runtimes: runtimes, layout: layout.databases).load()
        _ = try await LiveMailPort(manager: mail, runtimes: runtimes, layout: layout.mail).load()
        _ = try await LiveStoragePort(manager: storage, runtimes: runtimes, layout: layout.storage).load()

        #expect(await databases.calls == ["load"])
        #expect(await mail.calls == ["load", "register \(FakeServiceRuntimes.mail.id)"])
        #expect(await storage.calls == ["load", "register \(FakeServiceRuntimes.storage.id)"])
    }
}
