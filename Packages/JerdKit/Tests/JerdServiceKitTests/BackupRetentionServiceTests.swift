import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import Testing

@Suite struct BackupRetentionServiceTests {
    private struct Fixture {
        let directory: TemporaryDirectory
        let layout: DataLayout
        let system = FakeSystem()
        let first = UUID()
        let second = UUID()

        init() throws {
            directory = try TemporaryDirectory()
            layout = DataLayout(root: directory.url.appendingPathComponent("Jerd"))
            for folder in [layout.root, layout.storage.root, layout.storage.runtimeBackupsDirectory] {
                try OwnedDirectory.create(folder)
            }
            try write("fifteen bytes!!", to: backup(first).appendingPathComponent("data/object"))
            try write("fifteen bytes!!", to: backup(second).appendingPathComponent("settings.json"))
            try write("live objects", to: layout.storage.dataDirectory.appendingPathComponent("object"))
        }

        func backup(_ id: UUID) -> URL {
            layout.storage.runtimeBackupsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        }

        var service: BackupRetentionService {
            BackupRetentionService(layout: layout, startGate: StartGate(observer: system.observer))
        }
    }

    @Test(arguments: [false, true])
    func aPendingJournalProtectsEveryBackupAndCleanupKeepsCurrentData(pending: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        if pending { try write("{corrupt", to: fixture.layout.storage.runtimeUpdateJournal) }
        let rows = await fixture.service.inspect()
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.bytes == 15 && $0.isProtected == pending && $0.service == "Storage" })
        #expect(rows.map(\.id) == rows.map(\.id).sorted())
        let id = "storage/\(fixture.first.uuidString)"
        if pending {
            await #expect(throws: JerdError.unavailable("Complete runtime recovery before deleting service backups.")) {
                try await fixture.service.remove(id)
            }
            #expect(exists(fixture.backup(fixture.first)))
        } else {
            try await fixture.service.remove(id)
            #expect(!exists(fixture.backup(fixture.first)))
        }
        #expect(exists(fixture.backup(fixture.second)))
        #expect(text(fixture.layout.storage.dataDirectory.appendingPathComponent("object")) == "live objects")
    }

    @Test(arguments: ["storage/../../data", "storage", "mail/x", "web/\(UUID().uuidString)", "storage/a/b"])
    func anInvalidBackupIDIsRefused(_ id: String) async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        await #expect(throws: JerdError.invalid("The selected backup ID is invalid.")) {
            try await fixture.service.remove(id)
        }
    }

    @Test func aRunningServiceAndALinkedBackupPreventDeletion() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let lock = try InstanceLock.acquire(
            at: fixture.layout.storage.lockFile, messages: .init(unavailable: "x", busy: "held"))
        await #expect(throws: JerdError.locked("Stop this service before deleting a backup.")) {
            try await fixture.service.remove("storage/\(fixture.first.uuidString)")
        }
        lock.release()
        let target = fixture.directory.path("outside")
        try write("keep", to: target.appendingPathComponent("file"))
        let linked = UUID()
        try FileManager.default.createSymbolicLink(at: fixture.backup(linked), withDestinationURL: target)
        let row = try #require(await fixture.service.inspect().first { $0.id == "storage/\(linked.uuidString)" })
        #expect(row.isProtected && row.bytes == nil)
        await #expect(throws: (any Error).self) { try await fixture.service.remove(row.id) }
        #expect(text(target.appendingPathComponent("file")) == "keep")
    }

    @Test func aLiveSavedProcessPreventsDeletion() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let record = ActiveRunRecord(
            processID: 4_242, runtimeID: "rustfs", identity: nil, controller: nil, gracefulSignal: 15)
        try ActiveRunRecordFile.write(record, to: fixture.layout.storage.activeRunFile)
        fixture.system.setSavedProcessesAlive(true)
        await #expect(throws: (any Error).self) {
            try await fixture.service.remove("storage/\(fixture.first.uuidString)")
        }
        #expect(exists(fixture.backup(fixture.first)))
        #expect(exists(fixture.layout.storage.activeRunFile))
    }

    @Test func aBadServiceFolderGivesOneRowAndKeepsTheOtherService() async throws {
        let fixture = try Fixture()
        defer { fixture.directory.remove() }
        let mail = fixture.layout.mail
        try OwnedDirectory.create(mail.root)
        try FileManager.default.createSymbolicLink(
            at: mail.runtimeBackupsDirectory, withDestinationURL: fixture.directory.path("elsewhere"))
        let rows = await fixture.service.inspect()
        #expect(rows.count == 3)
        let problem = try #require(rows.first { $0.id == "mail" })
        #expect(problem.isProtected && problem.service == "Mail")
        #expect(rows.filter { $0.service == "Storage" }.count == 2)
    }
}
