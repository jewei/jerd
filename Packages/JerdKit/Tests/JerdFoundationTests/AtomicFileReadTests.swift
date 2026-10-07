import Darwin
import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@Suite struct AtomicFileReadTests {
    @Test func aFileAtTheExactLimitIsReadAndOneMoreByteIsRefused() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("record.json")
        try AtomicFile.write(Data(repeating: 65, count: 10), to: file)
        #expect(try AtomicFile.read(file, limit: 10) == Data(repeating: 65, count: 10))
        let error = try #require(throws: JerdError.self) { try AtomicFile.read(file, limit: 9) }
        #expect(
            error == .corrupt("The private file \(file.path) has an invalid owner, type, or size. It was preserved."))
    }

    @Test func aHardLinkedFileIsRefused() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("record.json")
        try AtomicFile.write(Data("x".utf8), to: file)
        #expect(link(file.path, folder.path("second").path) == 0)
        #expect(throws: JerdError.corrupt(invalid(file))) { try AtomicFile.read(file, limit: 100) }
    }

    @Test func aSymbolicLinkIsRefusedAsAnInvalidType() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let target = folder.path("target")
        try AtomicFile.write(Data("x".utf8), to: target)
        let file = folder.path("record.json")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        #expect(throws: JerdError.corrupt(invalid(file))) { try AtomicFile.read(file, limit: 100) }
    }

    @Test func aFIFOIsRefusedWithoutBlocking() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let fifo = folder.path("record.json")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: JerdError.corrupt(invalid(fifo))) { try AtomicFile.read(fifo, limit: 100) }
    }

    @Test func aFileOfAnotherOwnerIsRefused() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("registration.json")
        try AtomicFile.write(Data("x".utf8), to: file)
        #expect(throws: JerdError.corrupt(invalid(file))) {
            try AtomicFile.read(file, limit: 100, owner: geteuid() + 1)
        }
        #expect(try AtomicFile.read(file, limit: 100, owner: geteuid()) == Data("x".utf8))
    }

    @Test func aMissingFileIsUnavailableWithTheSystemCause() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("missing.json")
        let error = try #require(throws: JerdError.self) { try AtomicFile.read(file, limit: 100) }
        #expect(error == .unavailable("Cannot read private file: \(file.path) (No such file or directory)."))
    }

    @Test func anEmptyFileIsValid() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("empty")
        try AtomicFile.write(Data(), to: file)
        #expect(try AtomicFile.read(file, limit: 0).isEmpty)
    }

    private func invalid(_ file: URL) -> String {
        "The private file \(file.path) has an invalid owner, type, or size. It was preserved."
    }
}
