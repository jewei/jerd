import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct PathCanonicalizerTests {
    let files = PathCanonicalizer()

    @Test(arguments: ["relative/path", "", "/tmp/a\u{1}b", "/tmp/new\nline"])
    func relativePathsAndControlCharactersAreRejected(_ path: String) {
        #expect(throws: JerdError.invalid("Use an absolute directory path without control characters.")) {
            try files.canonicalDirectory(path)
        }
    }

    @Test func aMissingDirectoryNamesTheOriginalPath() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let missing = folder.path("missing").path
        #expect(throws: JerdError.invalid("Directory does not exist: \(missing)")) {
            try files.canonicalDirectory(missing)
        }
        let file = try folder.file("plain.txt")
        #expect(throws: JerdError.self) { try files.canonicalDirectory(file.path) }
    }

    @Test func linksDotsAndUnicodeResolveToOneCanonicalForm() throws {
        let folder = try TemporaryDirectory(" café 项目")
        defer { folder.remove() }
        let real = try folder.folder("real")
        let link = folder.path("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        #expect(try files.canonicalDirectory(link.path) == real.path)
        #expect(try files.canonicalDirectory(real.path + "/../real/.") == real.path)
    }

    @Test func thePrivatePrefixIsDroppedLikeFoundationDoes() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let canonical = try files.canonicalDirectory(folder.url.path)
        let privateForm = "/private" + canonical
        if FileManager.default.fileExists(atPath: privateForm) {
            #expect(try files.canonicalDirectory(privateForm) == canonical)
        }
        #expect(!canonical.hasPrefix("/private/var/"))
    }

    @Test func isFileFollowsLinksAndRejectsDirectories() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = try folder.file("a.txt", "x")
        let link = folder.path("a-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(files.isFile(file.path))
        #expect(files.isFile(link.path))
        #expect(!files.isFile(folder.url.path))
        #expect(!files.isFile(folder.path("missing").path))
    }
}
