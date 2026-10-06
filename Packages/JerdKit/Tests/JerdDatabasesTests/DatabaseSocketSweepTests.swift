import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdDatabases

/// A load removes the socket folders of runs that ended without a stop (spec E 7.2.4), but only
/// when it can prove that no process uses them.
@Suite struct DatabaseSocketSweepTests {
    /// A folder as a crashed run leaves it: the owner marker and a socket lock file.
    private func leftover(_ harness: DatabaseHarness, owner id: UUID) throws -> URL {
        let instance = harness.layout.instance(id)
        try OwnedDirectory.create(instance.root)
        let folder = try DatabaseSocketFolder.create(in: harness.socketRoot, owner: instance.root)
        try write("4242\n", to: folder.appendingPathComponent(".s.PGSQL.5432.lock"))
        return folder
    }

    private func saveRecord(_ harness: DatabaseHarness, for id: UUID) throws -> URL {
        let file = harness.layout.instance(id).activeRunFile
        let record = ActiveRunRecord(
            processID: 4_242, runtimeID: "postgresql-test", identity: nil, controller: nil, gracefulSignal: SIGINT)
        try ActiveRunRecordFile.write(record, to: file)
        return file
    }

    @Test func aLoadRemovesTheSocketFolderOfACrashedRunAndItsStaleRecord() async throws {
        let harness = try DatabaseHarness()
        let id = UUID()
        let crashed = try leftover(harness, owner: id)
        let record = try saveRecord(harness, for: id)
        _ = try await harness.manager().load()
        #expect(!exists(crashed))
        #expect(!exists(record))
        #expect(isLockFree(harness.layout.instance(id).lockFile))
    }

    @Test func aLoadKeepsTheFolderWhenTheSavedProcessMayLive() async throws {
        let harness = try DatabaseHarness()
        let id = UUID()
        let folder = try leftover(harness, owner: id)
        let record = try saveRecord(harness, for: id)
        harness.system.setSavedProcessesAlive(true)
        _ = try await harness.manager().load()
        #expect(exists(folder.appendingPathComponent(".s.PGSQL.5432.lock")))
        #expect(exists(record))
    }

    @Test func aLoadKeepsTheFolderOfAServiceThatAnotherManagerRuns() async throws {
        let harness = try DatabaseHarness()
        let running = try await harness.loadedManager()
        let service = try await running.add(name: "Main", runtimeID: harness.runtime(.postgresql).id, port: 25_450)
        try await running.start(service.id)
        let folders = try FileManager.default.contentsOfDirectory(atPath: harness.socketRoot.path)
        #expect(folders.count == 1)
        _ = try await harness.manager().load()
        #expect(try FileManager.default.contentsOfDirectory(atPath: harness.socketRoot.path) == folders)
        try await running.stopAll()
        #expect(try FileManager.default.contentsOfDirectory(atPath: harness.socketRoot.path).isEmpty)
    }

    @Test func aLoadKeepsFoldersThatItCannotProveToBeFromThisDataRoot() async throws {
        let harness = try DatabaseHarness()
        let unmarked = harness.socketRoot.appendingPathComponent("jerd-db-older-build", isDirectory: true)
        try OwnedDirectory.create(unmarked)
        let foreignOwner = harness.directory.path("Other/databases/instances/\(UUID().uuidString)")
        try OwnedDirectory.create(foreignOwner)
        let foreign = try DatabaseSocketFolder.create(in: harness.socketRoot, owner: foreignOwner)
        let missingOwner = harness.layout.instance(UUID()).root
        let orphan = try DatabaseSocketFolder.create(in: harness.socketRoot, owner: missingOwner)
        let unrelated = harness.socketRoot.appendingPathComponent("another-program", isDirectory: true)
        try OwnedDirectory.create(unrelated)
        _ = try await harness.manager().load()
        for folder in [unmarked, foreign, orphan, unrelated] { #expect(exists(folder), "\(folder.lastPathComponent)") }
    }
}
