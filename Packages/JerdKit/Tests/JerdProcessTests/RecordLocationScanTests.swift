import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdTestSupport
import Testing

@Suite struct RecordLocationScanTests {
    private func legacy(_ pid: Int32 = 99_999) -> Data { Data("{\"processID\":\(pid),\"runtimeID\":\"legacy\"}".utf8) }

    @Test func everyFamilyIsFoundInAFixedOrder() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()
        let records = [
            layout.environment.processRecord(second), layout.tunnels.instance(first).record,
            layout.databases.instance(second).record, layout.databases.instance(first).record, layout.storage.record,
            layout.mail.record,
        ]
        for record in records {
            try OwnedDirectory.create(record.folder)
            try AtomicFile.write(legacy(), to: record.recordFile)
        }
        try OwnedDirectory.create(layout.databases.instancesDirectory.appendingPathComponent("not-a-uuid"))
        try AtomicFile.write(
            legacy(), to: layout.environment.processesDirectory.appendingPathComponent("\(first.uuidString).txt"))
        let findings = await ProcessRecoveryService(layout: layout).inspect()
        #expect(
            findings.map(\.id) == [
                "Mail", "Storage", "Database/\(first.uuidString)", "Database/\(second.uuidString)",
                "Tunnel/\(first.uuidString)",
                "Web/\(second.uuidString)",
            ])
        #expect(
            findings.map(\.title) == [
                "Mail", "Storage", "Database 00000000", "Database 00000000", "Tunnel 00000000",
                "Web 00000000",
            ])
        #expect(findings.allSatisfy { $0.state == .stale })
    }

    @Test func aLinkedServiceFolderGivesOneErrorRowAndOtherServicesStillAppear() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let elsewhere = try TemporaryDirectory()
        defer { elsewhere.remove() }
        let layout = DataLayout(root: folder.url)
        try FileManager.default.createSymbolicLink(at: layout.mail.root, withDestinationURL: elsewhere.url)
        try AtomicFile.write(legacy(), to: elsewhere.path("active-run.json"))
        try OwnedDirectory.create(layout.storage.root)
        try AtomicFile.write(legacy(getpid()), to: layout.storage.activeRunFile)
        let findings = await ProcessRecoveryService(layout: layout).inspect()
        #expect(findings.map(\.id) == ["Mail", "Storage"])
        #expect(findings.map(\.state) == [.manual, .manual])
        #expect(findings[0].detail.hasPrefix("The directory \(layout.mail.root.path)"))
        #expect(!findings[0].canRecover)
    }

    @Test func aLinkedInstanceFolderIsSkipped() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let elsewhere = try TemporaryDirectory()
        defer { elsewhere.remove() }
        let layout = DataLayout(root: folder.url)
        try OwnedDirectory.create(layout.databases.instancesDirectory)
        try AtomicFile.write(legacy(), to: elsewhere.path("active-run.json"))
        let linked = layout.databases.instance(UUID()).root
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: elsewhere.url)
        #expect(await ProcessRecoveryService(layout: layout).inspect().isEmpty)
    }

    /// Regression test: a linked web record file is skipped, like a linked instance folder.
    @Test func aLinkedWebRecordFileIsSkipped() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let elsewhere = try TemporaryDirectory()
        defer { elsewhere.remove() }
        let layout = DataLayout(root: folder.url)
        try OwnedDirectory.create(layout.environment.processesDirectory)
        try AtomicFile.write(legacy(), to: elsewhere.path("record.json"))
        let linked = layout.environment.processRecord(UUID()).recordFile
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: elsewhere.path("record.json"))
        let plain = UUID()
        try AtomicFile.write(legacy(), to: layout.environment.processRecord(plain).recordFile)
        let findings = await ProcessRecoveryService(layout: layout).inspect()
        #expect(findings.map(\.id) == ["Web/\(plain.uuidString)"])
    }

    @Test func aCorruptRecordShowsAShortReasonNotADecoderDump() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        try OwnedDirectory.create(layout.mail.root)
        try AtomicFile.write(Data("{\"runtimeID\":\"x\"}".utf8), to: layout.mail.activeRunFile)
        let finding = try #require(await ProcessRecoveryService(layout: layout).inspect().first)
        #expect(finding.state == .manual)
        #expect(
            finding.detail
                == "The saved process record is invalid. It was preserved. A required value is missing: processID.")
    }
}
