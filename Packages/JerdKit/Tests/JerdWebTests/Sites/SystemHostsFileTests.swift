import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct SystemHostsFileTests {
    @Test func aHostsFileIsReadThroughALink() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = try folder.file("hosts", "127.0.0.1 localhost\n")
        let link = folder.path("hosts-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(try SystemHostsFile(url: link).read() == "127.0.0.1 localhost\n")
    }

    @Test func theSystemHostsFileIsReadable() throws {
        #expect(throws: Never.self) { try SystemHostsFile().read() }
    }

    @Test func missingLargeFolderAndNonUTF8FilesGiveAClearError() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let large = folder.path("large")
        try Data(repeating: 65, count: SystemHostsFile.sizeLimit + 1).write(to: large)
        let binary = folder.path("binary")
        try Data([0xFF, 0xFE, 0x00, 0xC3]).write(to: binary)
        for url in [folder.path("missing"), large, binary, folder.url] {
            #expect(throws: JerdError.self) { try SystemHostsFile(url: url).read() }
        }
    }
}
