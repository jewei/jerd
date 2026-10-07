import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@Suite struct FileDigestTests {
    private let abc = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    @Test func knownVectorsMatch() throws {
        #expect(FileDigest.hexSHA256(of: Data("abc".utf8)) == abc)
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let file = folder.path("abc")
        try Data("ab".utf8).write(to: file)
        #expect(HexEncoding.string(try FileDigest.sha256(of: file, appending: Data("c".utf8))) == abc)
    }

    @Test func aFileLargerThanOneChunkHashesLikeTheSameBytesInMemory() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let bytes = Data((0..<(FileDigest.chunkSize * 2 + 17)).map { UInt8(truncatingIfNeeded: $0 * 31) })
        let file = folder.path("large")
        try bytes.write(to: file)
        #expect(try FileDigest.hexSHA256(of: file) == FileDigest.hexSHA256(of: bytes))
    }

    @Test func aLinkOrAFolderIsRefused() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        try Data("x".utf8).write(to: folder.path("target"))
        try FileManager.default.createSymbolicLink(at: folder.path("link"), withDestinationURL: folder.path("target"))
        #expect(throws: JerdError.self) { try FileDigest.hexSHA256(of: folder.path("link")) }
        #expect(throws: JerdError.self) { try FileDigest.hexSHA256(of: folder.url) }
    }

    @Test func onlyLowercaseSixtyFourDigitHexIsADigest() {
        #expect(FileDigest.isSHA256Hex(abc))
        #expect(!FileDigest.isSHA256Hex(abc.uppercased()))
        #expect(!FileDigest.isSHA256Hex(String(abc.dropLast())))
    }
}
