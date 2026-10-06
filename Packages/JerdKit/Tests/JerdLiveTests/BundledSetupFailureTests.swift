import Foundation
import JerdDatabases
import JerdFoundation
import JerdMail
import JerdStorage
import Testing

@testable import JerdLive

@Suite("Bundled setup failures")
struct BundledSetupFailureTests {
    static let unavailable = JerdError.unavailable("The bundled runtime payloads are missing from this build.")

    @Test func aFailedDatabaseSetupReportsItsReasonAfterTheLoad() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let setup = BundledSetupRecord()
        let layout = temporary.layout.databases
        let failing = LiveDatabasesPort(
            manager: RecordingDatabaseManager(), runtimes: FakeServiceRuntimes(failure: Self.unavailable),
            layout: layout, setup: setup)

        _ = try await failing.load()

        #expect(await failing.runtimeSetupFailure() == Self.unavailable.message)
        let retry = LiveDatabasesPort(
            manager: RecordingDatabaseManager(), runtimes: FakeServiceRuntimes(), layout: layout, setup: setup)
        _ = try await retry.load()
        #expect(await retry.runtimeSetupFailure() == nil)
    }

    @Test func aDatabaseLoadThatNeedsNoSetupReportsNoFailure() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let postgres = DatabaseRuntime(id: "pg", engine: .postgresql, version: "18.6", path: "/runtimes/pg")
        let manager = RecordingDatabaseManager(
            DatabaseConfiguration(runtimes: [FakeServiceRuntimes.mysql, postgres, FakeServiceRuntimes.redis]))
        let port = LiveDatabasesPort(
            manager: manager, runtimes: FakeServiceRuntimes(failure: Self.unavailable),
            layout: temporary.layout.databases)

        _ = try await port.load()

        #expect(await port.runtimeSetupFailure() == nil)
    }

    @Test func aFailedMailSetupReportsItsReasonAndASuccessClearsIt() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let setup = BundledSetupRecord()
        let layout = temporary.layout.mail
        let failing = LiveMailPort(
            manager: RecordingMailManager(), runtimes: FakeServiceRuntimes(failure: Self.unavailable), layout: layout,
            setup: setup)

        _ = try await failing.load()

        #expect(await failing.runtimeSetupFailure() == Self.unavailable.message)
        let retry = LiveMailPort(
            manager: RecordingMailManager(), runtimes: FakeServiceRuntimes(), layout: layout, setup: setup)
        _ = try await retry.load()
        #expect(await retry.runtimeSetupFailure() == nil)
    }

    @Test func aFailedStorageSetupReportsItsReasonAndASuccessClearsIt() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let setup = BundledSetupRecord()
        let layout = temporary.layout.storage
        let failing = LiveStoragePort(
            manager: RecordingStorageManager(), runtimes: FakeServiceRuntimes(failure: Self.unavailable),
            layout: layout, setup: setup)

        _ = try await failing.load()

        #expect(await failing.runtimeSetupFailure() == Self.unavailable.message)
        let retry = LiveStoragePort(
            manager: RecordingStorageManager(), runtimes: FakeServiceRuntimes(), layout: layout, setup: setup)
        _ = try await retry.load()
        #expect(await retry.runtimeSetupFailure() == nil)
    }

    @Test func copiesOfALivePortShareOneSetupRecord() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let port = LiveMailPort(
            manager: RecordingMailManager(), runtimes: FakeServiceRuntimes(failure: Self.unavailable),
            layout: temporary.layout.mail)
        let copy = port

        _ = try await port.load()

        #expect(await copy.runtimeSetupFailure() == Self.unavailable.message)
    }

    @Test func aCorruptSettingsFileFailsTheLoadAndRecordsNoSetup() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let port = LiveStoragePort(
            manager: RecordingStorageManager(loadFailure: .corrupt("The settings are corrupt.")),
            runtimes: FakeServiceRuntimes(failure: Self.unavailable), layout: temporary.layout.storage)

        await #expect(throws: JerdError.corrupt("The settings are corrupt.")) { try await port.load() }
        #expect(await port.runtimeSetupFailure() == nil)
    }
}
