import Darwin
import Foundation
import JerdFoundation
import Testing

@Suite struct AtomicFileWriteTests {
    @Test(arguments: [AtomicFile.Durability.standard, .full])
    func writeCreatesAPrivateFileWithTheExactBytes(durability: AtomicFile.Durability) throws {
        let folder = try TemporaryDirectory(" atomic café")
        defer { folder.remove() }
        let file = folder.path("record.json")
        try AtomicFile.write(Data("first".utf8), to: file, durability: durability)
        try AtomicFile.write(Data("second".utf8), to: file, durability: durability)
        #expect(contents(file) == Data("second".utf8))
        #expect(permissions(file) == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path) == ["record.json"])
    }

    @Test func writeReplacesASymbolicLinkWithoutWritingThroughIt() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let target = folder.path("target")
        try Data("keep".utf8).write(to: target)
        let link = folder.path("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try AtomicFile.write(Data("new".utf8), to: link)
        #expect(contents(target) == Data("keep".utf8))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == nil)
        #expect(contents(link) == Data("new".utf8))
    }

    @Test func writeIntoAMissingFolderFailsAndCreatesNothing() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        #expect(throws: JerdError.self) { try AtomicFile.write(Data("x".utf8), to: folder.path("missing/file")) }
        #expect(FileProbe.presence(at: folder.path("missing")) == .absent)
    }

    @Test func aFailedRenameRemovesTheTemporaryFile() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let occupied = folder.path("occupied")
        try FileManager.default.createDirectory(
            at: occupied.appendingPathComponent("child"), withIntermediateDirectories: true)
        let error = try #require(throws: JerdError.self) { try AtomicFile.write(Data("x".utf8), to: occupied) }
        #expect(error.kind == .unavailable)
        #expect(error.message.hasPrefix("Cannot save \(occupied.path)"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path) == ["occupied"])
    }

    @Test func removeDeletesALinkButNotItsTargetAndIgnoresAMissingFile() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let target = folder.path("target")
        try Data("keep".utf8).write(to: target)
        let link = folder.path("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        try AtomicFile.remove(link)
        try AtomicFile.remove(link)
        #expect(FileProbe.presence(at: link) == .absent)
        #expect(contents(target) == Data("keep".utf8))
    }
}
