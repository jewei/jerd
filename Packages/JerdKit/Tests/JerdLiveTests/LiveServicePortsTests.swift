import Foundation
import JerdDatabases
import JerdFoundation
import JerdMail
import JerdStorage
import Testing

@testable import JerdLive

@Suite("Live service ports")
struct LiveServicePortsTests {
    static let corrupt = JerdError.corrupt("The settings are corrupt.")

    // MARK: Databases

    @Test func databaseLoadInstallsOnlyTheEnginesWithoutARuntime() async throws {
        let manager = RecordingDatabaseManager(DatabaseConfiguration(runtimes: [FakeServiceRuntimes.mysql]))
        let runtimes = FakeServiceRuntimes()
        let port = LiveDatabasesPort(manager: manager, runtimes: runtimes, layout: try Fixture.layout().databases)

        let snapshot = try await port.load()

        #expect(await runtimes.databaseRequests == [[.mysql]])
        #expect(await manager.registered == [[FakeServiceRuntimes.redis]])
        #expect(snapshot.configuration.runtimes == [FakeServiceRuntimes.mysql, FakeServiceRuntimes.redis])
    }

    @Test func databaseLoadInstallsNothingWhenEveryEngineHasARuntime() async throws {
        let postgres = DatabaseRuntime(id: "pg", engine: .postgresql, version: "18.6", path: "/runtimes/pg")
        let manager = RecordingDatabaseManager(
            DatabaseConfiguration(runtimes: [FakeServiceRuntimes.mysql, postgres, FakeServiceRuntimes.redis]))
        let runtimes = FakeServiceRuntimes()

        _ = try await LiveDatabasesPort(manager: manager, runtimes: runtimes, layout: try Fixture.layout().databases)
            .load()

        #expect(await runtimes.databaseRequests.isEmpty)
    }

    @Test func corruptDatabaseSettingsFailTheLoadBeforeAnyInstall() async throws {
        let manager = RecordingDatabaseManager(loadFailure: Self.corrupt)
        let runtimes = FakeServiceRuntimes()
        let port = LiveDatabasesPort(manager: manager, runtimes: runtimes, layout: try Fixture.layout().databases)

        await #expect(throws: Self.corrupt) { try await port.load() }
        #expect(await runtimes.databaseRequests.isEmpty)
    }

    @Test func aFailedBundledDatabaseSetupKeepsTheLoadUsable() async throws {
        let manager = RecordingDatabaseManager()
        let port = LiveDatabasesPort(
            manager: manager, runtimes: FakeServiceRuntimes(failure: .unavailable("No payloads.")),
            layout: try Fixture.layout().databases)

        let snapshot = try await port.load()

        #expect(snapshot.configuration.runtimes.isEmpty)
        #expect(await manager.registered.isEmpty)
    }

    @Test func databaseStopAllFailureReachesTheQuit() async throws {
        let manager = RecordingDatabaseManager()
        await manager.failStopAll(.timedOut("MySQL did not stop."))
        let port = LiveDatabasesPort(
            manager: manager, runtimes: FakeServiceRuntimes(), layout: try Fixture.layout().databases)

        await #expect(throws: JerdError.timedOut("MySQL did not stop.")) { try await port.stopAll() }
    }

    @Test func databaseFilesFollowTheInstanceLayout() async throws {
        let layout = try Fixture.layout().databases
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
        let manager = RecordingMailManager()
        let runtimes = FakeServiceRuntimes()
        let port = LiveMailPort(manager: manager, runtimes: runtimes, layout: try Fixture.layout().mail)

        let snapshot = try await port.load()
        _ = try await port.load()

        #expect(snapshot.settings.runtime == FakeServiceRuntimes.mail)
        #expect(await runtimes.mailRequests == 1)
    }

    @Test func corruptMailSettingsFailTheLoadBeforeAnyInstall() async throws {
        let runtimes = FakeServiceRuntimes()
        let port = LiveMailPort(
            manager: RecordingMailManager(loadFailure: Self.corrupt), runtimes: runtimes,
            layout: try Fixture.layout().mail)

        await #expect(throws: Self.corrupt) { try await port.load() }
        #expect(await runtimes.mailRequests == 0)
    }

    @Test func aFailedMailpitSetupKeepsTheLoadUsable() async throws {
        let port = LiveMailPort(
            manager: RecordingMailManager(), runtimes: FakeServiceRuntimes(failure: .unavailable("No payloads.")),
            layout: try Fixture.layout().mail)

        #expect(try await port.load().settings.runtime == nil)
    }

    @Test func mailFilesAreTheInboxAndTheServerLog() async throws {
        let layout = try Fixture.layout().mail
        let files = await LiveMailPort(manager: RecordingMailManager(), runtimes: FakeServiceRuntimes(), layout: layout)
            .files()

        #expect(files.dataFolder == layout.inboxDirectory)
        #expect(files.log == layout.logFile)
    }

    // MARK: Storage

    @Test func storageLoadInstallsRustFSOnlyWhenNoRuntimeIsSaved() async throws {
        let manager = RecordingStorageManager()
        let runtimes = FakeServiceRuntimes()
        let port = LiveStoragePort(manager: manager, runtimes: runtimes, layout: try Fixture.layout().storage)

        let snapshot = try await port.load()
        _ = try await port.load()

        #expect(snapshot.settings.runtime == FakeServiceRuntimes.storage)
        #expect(await runtimes.storageRequests == 1)
    }

    @Test func corruptStorageSettingsFailTheLoadBeforeAnyInstall() async throws {
        let runtimes = FakeServiceRuntimes()
        let port = LiveStoragePort(
            manager: RecordingStorageManager(loadFailure: Self.corrupt), runtimes: runtimes,
            layout: try Fixture.layout().storage)

        await #expect(throws: Self.corrupt) { try await port.load() }
        #expect(await runtimes.storageRequests == 0)
    }

    @Test func storageForwardsBucketWorkUnchanged() async throws {
        let manager = RecordingStorageManager()
        let port = LiveStoragePort(
            manager: manager, runtimes: FakeServiceRuntimes(), layout: try Fixture.layout().storage)

        try await port.addBucket(name: "uploads", publicRead: false)
        try await port.retryBucket("uploads")
        try await port.refreshBuckets()

        #expect(await manager.calls == ["addBucket uploads false", "retryBucket uploads", "refreshBuckets"])
    }

    @Test func storageFilesAreTheDataFolderAndTheServerLog() async throws {
        let layout = try Fixture.layout().storage
        let files = await LiveStoragePort(
            manager: RecordingStorageManager(), runtimes: FakeServiceRuntimes(), layout: layout
        ).files()

        #expect(files.dataFolder == layout.dataDirectory)
        #expect(files.log == layout.logFile)
    }
}
