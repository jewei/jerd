import Darwin
import Foundation
import JerdFoundation
import Testing

@testable import JerdSystem

@Suite struct GuardedFileSwapTests {
    private let original = Data("127.0.0.1 localhost\n".utf8)

    private func makeFile(_ folder: TemporaryDirectory, mode: Int = 0o644) throws -> URL {
        let url = folder.path("hosts")
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        return url
    }

    private func swap(
        _ url: URL, preExchange: (@Sendable () throws -> Void)? = nil,
        preRestore: (@Sendable () throws -> Void)? = nil
    ) -> GuardedFileSwap {
        GuardedFileSwap(
            url: url, expectedOwner: getuid(), lockTimeout: .milliseconds(200),
            hooks: GuardedFileSwapHooks(preExchange: preExchange, preRestore: preRestore))
    }

    @Test func replaceKeepsModeAndAttributesAndLeavesNoStagingFile() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let url = try makeFile(folder, mode: 0o640)
        let value = Array("keep".utf8)
        #expect(value.withUnsafeBytes { setxattr(url.path, "com.jerd.test", $0.baseAddress, $0.count, 0, 0) } == 0)
        let file = swap(url)
        let next = Data("127.0.0.1 localhost\n127.0.0.1 demo.test\n".utf8)
        try await file.replace(expected: original, with: next)
        #expect(try file.read() == next)
        #expect(try folder.names(withPrefix: ".jerd-hosts-").isEmpty)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o640)
        var read = [UInt8](repeating: 0, count: 4)
        #expect(getxattr(url.path, "com.jerd.test", &read, read.count, 0, 0) == 4)
        #expect(read == value)
    }

    /// Regression test: the new file gets a new modification time, so resolvers see the change.
    @Test func replaceSetsANewModificationTime() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let url = try makeFile(folder)
        let old = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        try await swap(url).replace(expected: original, with: Data("next\n".utf8))
        let modified = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
        #expect(modified.timeIntervalSince(old) > 1_000_000)
    }

    @Test func refusesAnUnexpectedCurrentContent() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let url = try makeFile(folder)
        await #expect(throws: JerdError.invalid("The hosts file changed. Retry the setup.")) {
            try await swap(url).replace(expected: Data("other".utf8), with: Data())
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func refusesLinksHardLinksAndOtherOwners() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let url = try makeFile(folder)
        let alias = folder.path("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: url)
        #expect(throws: JerdError.invalid("Cannot open the hosts file safely.")) { try swap(alias).read() }
        let shape = JerdError.invalid("The hosts file has an unexpected type, owner, link count, or size.")
        #expect(throws: shape) { try GuardedFileSwap(url: url, expectedOwner: getuid() + 1).read() }
        try FileManager.default.linkItem(at: url, to: folder.path("second-link"))
        #expect(throws: shape) { try swap(url).read() }
    }

    @Test func refusesOversizedFilesAndUpdates() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let url = try makeFile(folder)
        await #expect(throws: JerdError.invalid("The hosts update is too large.")) {
            try await swap(url).replace(expected: original, with: Data(count: 1_048_577))
        }
        try Data(count: 1_048_577).write(to: url)
        #expect(throws: JerdError.invalid("The hosts file has an unexpected type, owner, link count, or size.")) {
            try swap(url).read()
        }
    }

    /// Regression test: a held lock gives a bounded wait and a `.locked` error, never a hang.
    @Test func aHeldLockTimesOutInsteadOfBlocking() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let url = try makeFile(folder)
        let holder = open(url.path, O_RDONLY)
        defer { close(holder) }
        #expect(flock(holder, LOCK_EX | LOCK_NB) == 0)
        await #expect(throws: JerdError.locked("Another process holds a lock on the hosts file. Close it, then retry."))
        {
            try await swap(url).replace(expected: original, with: Data("next".utf8))
        }
        #expect(try Data(contentsOf: url) == original)
        flock(holder, LOCK_UN)
        try await swap(url).replace(expected: original, with: Data("next".utf8))
    }

    @Test func aRacingWriterKeepsItsContent() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let url = try makeFile(folder)
        let raced = Data("127.0.0.1 raced.test\n".utf8)
        let file = swap(url, preExchange: { try raced.write(to: url, options: .atomic) })
        await #expect(throws: JerdError.invalid("The hosts file changed during setup. Retry the operation.")) {
            try await file.replace(expected: original, with: Data("127.0.0.1 replacement.test\n".utf8))
        }
        #expect(try Data(contentsOf: url) == raced)
        #expect(try folder.names(withPrefix: ".jerd-hosts-").isEmpty)
    }

    @Test(arguments: ["permissions", "attribute", "inode"])
    func aRacedMetadataChangeIsRestoredNotOverwritten(change: String) async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let url = try makeFile(folder, mode: 0o640)
        var before = stat()
        #expect(lstat(url.path, &before) == 0)
        let original = original
        let file = swap(
            url,
            preExchange: {
                switch change {
                case "permissions": chmod(url.path, 0o600)
                case "attribute":
                    _ = Array("keep".utf8).withUnsafeBytes {
                        setxattr(url.path, "com.jerd.race", $0.baseAddress, $0.count, 0, 0)
                    }
                default: try original.write(to: url, options: .atomic)
                }
            })
        await #expect(throws: (any Error).self) { try await file.replace(expected: original, with: Data("next".utf8)) }
        #expect(try Data(contentsOf: url) == original)
        var after = stat()
        #expect(lstat(url.path, &after) == 0)
        switch change {
        case "permissions": #expect(after.st_mode & 0o777 == 0o600)
        case "attribute": #expect(getxattr(url.path, "com.jerd.race", nil, 0, 0, 0) == 4)
        default: #expect(after.st_ino != before.st_ino)
        }
        #expect(try folder.names(withPrefix: ".jerd-hosts-").isEmpty)
    }

    @Test func aSecondWriterDuringRestorationKeepsBothFiles() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let url = try makeFile(folder)
        let first = Data("127.0.0.1 first.test\n".utf8)
        let second = Data("127.0.0.1 second.test\n".utf8)
        let file = swap(
            url, preExchange: { try first.write(to: url, options: .atomic) },
            preRestore: { try second.write(to: url, options: .atomic) })
        do {
            try await file.replace(expected: original, with: Data("replacement".utf8))
            Issue.record("Expected a partial change")
        } catch let error as JerdError {
            #expect(error.kind == .partialChange)
            #expect(error.message.contains(folder.path(".jerd-hosts-").path))
        }
        #expect(try Data(contentsOf: url) == first)
        let retained = try folder.names(withPrefix: ".jerd-hosts-")
        #expect(retained.count == 1)
        #expect(try Data(contentsOf: folder.path(try #require(retained.first))) == second)
    }

    @Test func aFIFOAtTheDestinationIsRefusedWithoutBlockingAndKept() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let url = try makeFile(folder)
        let file = swap(
            url,
            preExchange: {
                try FileManager.default.removeItem(at: url)
                #expect(mkfifo(url.path, 0o600) == 0)
            })
        await #expect(throws: (any Error).self) { try await file.replace(expected: original, with: Data("next".utf8)) }
        var info = stat()
        #expect(lstat(url.path, &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFIFO)
        #expect(throws: (any Error).self) { try file.read() }
        #expect(try folder.names(withPrefix: ".jerd-hosts-").isEmpty)
    }
}
