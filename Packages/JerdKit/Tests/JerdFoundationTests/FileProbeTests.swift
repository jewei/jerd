import Darwin
import Foundation
import JerdFoundation
import Testing

@Suite struct FileProbeTests {
    @Test func onlyAMissingPathIsAbsent() throws {
        let folder = try TemporaryDirectory(" probe")
        defer { folder.remove() }
        #expect(FileProbe.presence(at: folder.path("missing")) == .absent)
        #expect(!FileProbe.presence(at: folder.path("missing")).mayExist)
    }

    @Test func aDanglingSymbolicLinkIsPresent() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        try FileManager.default.createSymbolicLink(at: folder.path("link"), withDestinationURL: folder.path("gone"))
        #expect(FileProbe.presence(at: folder.path("link")) == .present)
    }

    @Test func aPathBelowAFileIsUnknownAndTreatedAsPresent() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        try Data().write(to: folder.path("file"))
        let presence = FileProbe.presence(at: folder.path("file/child"))
        #expect(presence == .unknown(errno: ENOTDIR))
        #expect(presence.mayExist)
    }

    @Test func anUnreadableFolderGivesUnknownNotAbsent() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let locked = folder.path("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        chmod(locked.path, 0)
        defer { chmod(locked.path, 0o700) }
        #expect(FileProbe.presence(at: locked.appendingPathComponent("record.json")) == .unknown(errno: EACCES))
    }
}
