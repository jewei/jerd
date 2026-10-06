import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdStorage

@Suite struct StorageManagerTests {
    @Test func registeringARuntimeSuggestsFreePortsAndKeepsTheRuntime() async throws {
        let harness = try await StorageHarness()
        harness.lsof.occupy(9_000)
        let manager = harness.manager()
        await #expect(throws: StorageMessages.notLoaded) { try await manager.start() }
        #expect(try await manager.load() == StorageSettings())
        await #expect(throws: StorageMessages.runtimeMissing) { try await manager.start() }
        try await manager.registerRuntime(harness.runtime)
        #expect(await manager.snapshot().settings.ports == StoragePorts(api: 9_001, console: 9_002))
        await #expect(throws: StorageMessages.runtimeChanged) {
            try await manager.registerRuntime(harness.updatedRuntime())
        }
        #expect(try await harness.manager().load().runtime == harness.runtime)
    }

    @Test func aStartRunsRustFSWithItsKeysOutOfArgumentsAndAStopKeepsTheData() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        harness.server.update { $0.buckets = ["app-uploads"] }
        try await manager.start()
        let snapshot = await manager.snapshot()
        #expect(snapshot.processID != nil && snapshot.availableBuckets == ["app-uploads"])
        let credentials = try await manager.credentials()
        let request = try #require(await harness.processes.requests.last)
        #expect(!request.arguments.joined().contains(credentials.secretKey))
        #expect(!request.environment.values.contains(credentials.secretKey))
        let marker = try MarkerFile.read(StorageInitializedMarker.self, from: harness.storage.initializedMarkerFile)
        #expect(marker.formatHash == FileDigest.hexSHA256(of: StorageHarness.format))
        try await manager.stop()
        let stopped = await manager.snapshot()
        #expect(stopped.state == .stopped && stopped.availableBuckets.isEmpty)
        #expect(try await manager.credentials() == credentials)
        #expect(exists(harness.storage.formatFile) && !exists(harness.storage.activeRunFile))
        #expect(await harness.processes.stopPolicies == [.graceful(signal: SIGTERM, timeout: .seconds(30))])
    }

    @Test func aPreviousLiveProcessAndAVersionMismatchCreateNoData() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        let record = Data("{\"processID\":\(getpid()),\"runtimeID\":\"rustfs\"}".utf8)
        try AtomicFile.write(record, to: harness.storage.activeRunFile)
        harness.system.setSavedProcessesAlive(true)
        await #expect(throws: (any Error).self) { try await manager.start() }
        #expect(contents(harness.storage.activeRunFile) == record)
        #expect(kill(getpid(), 0) == 0)
        harness.system.setSavedProcessesAlive(false)
        harness.setVersion("2.0.0")
        await #expect(throws: JerdError.unavailable(StorageMessages.versionMismatch)) { try await manager.start() }
        #expect(!exists(harness.storage.dataDirectory) && !exists(harness.storage.credentialsFile))
        #expect(await harness.processes.requests.isEmpty)
    }

    @Test(arguments: [true, false])
    func anOccupiedPortFailsTheSaveOfABucketAndCreatesNothing(api: Bool) async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        harness.lsof.occupy(api ? 9_000 : 9_001)
        await #expect {
            try await manager.addBucket(name: "safe-uploads", publicRead: false)
        } throws: { error in
            (error as? JerdError)?.message.contains("occupied") == true
        }
        let snapshot = await manager.snapshot()
        #expect(snapshot.processID == nil && snapshot.settings.buckets.isEmpty)
        #expect(!exists(harness.storage.credentialsFile))
    }

    @Test func aReadinessTimeoutShowsTheRedactedEndOfTheLog() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        harness.server.update { $0.consoleStatus = 500 }
        try OwnedDirectory.create(harness.storage.root)
        _ = try StorageData(layout: harness.storage).prepare(for: harness.runtime)
        let secret = try await manager.credentials().secretKey
        await harness.processes.setLogOutput("rustfs: bad key \(secret)\n")
        await #expect {
            try await manager.start()
        } throws: { error in
            guard let error = error as? JerdError, error.kind == .timedOut else { return false }
            return error.message == "RustFS did not become ready within 45 seconds. rustfs: bad key [redacted]\n"
        }
    }

    @Test func anUnexpectedExitIsDetectedAndHidesTheBucketList() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        await harness.processes.setLogOutput("panic: disk\n")
        try await manager.start()
        await harness.processes.exitAll()
        _ = await manager.snapshot()
        #expect(
            await eventually {
                await manager.snapshot().state == .failed(reason: "The RustFS process exited. panic: disk\n")
            })
        #expect(await manager.snapshot().availableBuckets.isEmpty)
        #expect(isLockFree(harness.storage.lockFile))
    }

    @Test func editMovesStoppedStorageAndChecksTheRecordUnderTheLock() async throws {
        let harness = try await StorageHarness()
        let manager = try await harness.loadedManager()
        let ports = StoragePorts(api: 19_000, console: 19_001)
        try await manager.start()
        await #expect(throws: StorageMessages.stopBeforeEditing) { try await manager.edit(ports: ports) }
        try await manager.stop()
        let record = Data("{\"processID\":\(getpid()),\"runtimeID\":\"rustfs\"}".utf8)
        try AtomicFile.write(record, to: harness.storage.activeRunFile)
        harness.system.setSavedProcessesAlive(true)
        await #expect(throws: (any Error).self) { try await manager.edit(ports: ports) }
        #expect(contents(harness.storage.activeRunFile) == record)
        harness.system.setSavedProcessesAlive(false)
        try await manager.edit(ports: ports)
        #expect(await manager.snapshot().settings.ports == ports)
        try await manager.start()
        #expect(try #require(await harness.processes.requests.last).arguments.contains("127.0.0.1:19000"))
        try await manager.stop()
    }
}
