import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@Suite struct ActiveRunRecordTests {
    private let oldRecord = """
        {"processID":42,"runtimeID":"rt","gracefulSignal":15,\
        "controller":{"auditWords":[1,2,3,4,5,6,7,8],"bootSeconds":3,"processID":7,"userID":501,"startedSeconds":1,\
        "executable":"\\/Applications\\/Jerd.app","startedMicroseconds":2},\
        "identity":{"auditWords":[1,2,3,4,5,6,7,8],"bootSeconds":3,"processID":42,"userID":501,"startedSeconds":1,\
        "executable":"\\/bin\\/x","startedMicroseconds":2}}
        """

    private func write(_ text: String, in folder: TemporaryDirectory) throws -> URL {
        let file = folder.path("active-run.json")
        try AtomicFile.write(Data(text.utf8), to: file)
        return file
    }

    @Test func recordsWrittenByOldBuildsAreRead() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let record = try ActiveRunRecordFile.read(try write(oldRecord, in: folder))
        #expect(record.processID == 42)
        #expect(record.identity?.executable == "/bin/x")
        #expect(record.controller?.processID == 7)
        #expect(record.signal == SIGTERM)
        #expect(record.descendants == nil)
    }

    @Test func legacyAndFallbackFormsAreRead() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let legacy = try ActiveRunRecordFile.read(try write("{\"processID\":42,\"runtimeID\":\"legacy\"}", in: folder))
        #expect(legacy.identity == nil && legacy.controller == nil && legacy.gracefulSignal == nil)
        #expect(legacy.signal == SIGTERM)
        let fallback = try ActiveRunRecordFile.read(
            try write("{\"processID\":42,\"runtimeID\":\"PHP 8.4.0\",\"gracefulSignal\":3}", in: folder))
        #expect(fallback.signal == SIGQUIT)
    }

    @Test func writesUseTheCompactEncodingAndOmitMissingValues() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("active-run.json")
        let record = ActiveRunRecord(
            processID: 42, runtimeID: "rt", identity: IdentityFactory.make(pid: 42), controller: nil, gracefulSignal: 2)
        try ActiveRunRecordFile.write(record, to: file)
        let saved = text(file)
        #expect(!saved.contains("\n") && !saved.contains(" "))
        #expect(saved.contains("\"executable\":\"\\/bin\\/x\""))
        #expect(!saved.contains("controller") && !saved.contains("descendants"))
        #expect(try ActiveRunRecordFile.read(file) == record)
    }

    @Test(arguments: [
        "{\"processID\":1,\"runtimeID\":\"x\"}",
        "{\"processID\":42,\"runtimeID\":\"x\",\"identity\":{\"processID\":43,\"userID\":501,\"startedSeconds\":1,\"startedMicroseconds\":2,\"bootSeconds\":3,\"executable\":\"x\"}}",
        "corrupt", "{\"runtimeID\":\"x\"}",
    ])
    func invalidRecordsAreCorruptAndPreserved(_ text: String) throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = try write(text, in: folder)
        let error = try #require(throws: JerdError.self) { try ActiveRunRecordFile.read(file) }
        #expect(error.kind == .corrupt)
        #expect(error.message.hasPrefix("The saved process record is invalid. It was preserved. "))
        #expect(contents(file) == Data(text.utf8))
    }

    @Test func oversizedWritesPreserveThePreviousReadableRecord() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("active-run.json")
        let identity = IdentityFactory.make(pid: 42)
        let original = ActiveRunRecord(
            processID: 42, runtimeID: "fixture", identity: identity, controller: identity, gracefulSignal: 15)
        try ActiveRunRecordFile.write(original, to: file)
        let bytes = contents(file)
        let large = IdentityFactory.make(pid: 43, executable: String(repeating: "x", count: 131_072))
        for children in [Array(repeating: identity, count: 1_025), [large]] {
            var oversized = original
            oversized.descendants = children
            #expect(throws: JerdError.self) { try ActiveRunRecordFile.write(oversized, to: file) }
            #expect(contents(file) == bytes)
            #expect(try ActiveRunRecordFile.read(file) == original)
        }
    }

    @Test func onlyTheHolderOfTheMatchingLockCanDeleteARecord() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let location = DataLayout(root: folder.url).mail.record
        try OwnedDirectory.create(location.folder)
        try AtomicFile.write(Data(oldRecord.utf8), to: location.recordFile)
        let messages = InstanceLock.Messages(unavailable: "x", busy: "y")
        let wrong = try InstanceLock.acquire(
            at: location.folder.appendingPathComponent("other.lock"), messages: messages)
        #expect(throws: JerdError.invalid("Hold the lock of Mail before changing its process record.")) {
            try ActiveRunRecordFile.remove(location, holding: wrong)
        }
        let lock = try InstanceLock.acquire(at: location.lockFile, messages: messages)
        lock.release()
        #expect(throws: JerdError.self) { try ActiveRunRecordFile.remove(location, holding: lock) }
        #expect(FileProbe.presence(at: location.recordFile) == .present)
        let held = try InstanceLock.acquire(at: location.lockFile, messages: messages)
        try ActiveRunRecordFile.remove(location, holding: held)
        #expect(FileProbe.presence(at: location.recordFile) == .absent)
    }
}
