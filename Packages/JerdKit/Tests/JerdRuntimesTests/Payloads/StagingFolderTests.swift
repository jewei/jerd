import Foundation
import JerdFoundation
import JerdRuntimes
import Testing

@Suite struct StagingFolderTests {
    private func names(_ folder: TemporaryFolder) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.url.path).sorted()
    }

    /// A staging folder whose owner still lives is in use and is never removed.
    @Test func cleanupRemovesOnlyFoldersWithoutALiveOwner() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try folder.write("partial", to: ".install-ABANDONED/payload/file")
        let inUse = try StagingFolder(in: folder.url)
        try Data("work".utf8).write(to: try inUse.folder("payload").appendingPathComponent("file"))
        #expect(StagingFolder.removeAbandoned(in: folder.url) == [".install-ABANDONED"])
        #expect(try names(folder) == [inUse.url.lastPathComponent])
        inUse.remove()
    }

    @Test func folderOfAnEndedOwnerIsAbandoned() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let name = try { () throws -> String in
            let ended = try StagingFolder(in: folder.url)
            return ended.url.lastPathComponent
        }()
        #expect(StagingFolder.removeAbandoned(in: folder.url) == [name])
        #expect(try names(folder).isEmpty)
    }

    @Test func cleanupKeepsLinksFilesAndOtherNames() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try folder.write("keep", to: "target/file")
        try folder.write("keep", to: ".install-file")
        try folder.write("keep", to: "php-8.5.11-arm64/file")
        try FileManager.default.createSymbolicLink(
            at: folder.path(".install-link"), withDestinationURL: folder.path("target"))
        #expect(StagingFolder.removeAbandoned(in: folder.url).isEmpty)
        #expect(try names(folder) == [".install-file", ".install-link", "php-8.5.11-arm64", "target"])
        #expect(FileProbe.presence(at: folder.path("target/file")) == .present)
    }

    @Test func copiesShareTheLockOfTheFolder() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var copies: [StagingFolder] = [try StagingFolder(in: folder.url)]
        let copy = copies[0]
        copies.removeAll()
        #expect(StagingFolder.removeAbandoned(in: folder.url).isEmpty)
        copy.remove()
    }
}
