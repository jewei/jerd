import Foundation
import JerdFoundation
import JerdManifest
import Testing

@Suite struct PayloadFolderIDTests {
    @Test func canonicalListIsSortedByPathWithTabsAndModeFlags() throws {
        let files = try records([("b", "2", false), ("a/x", "1", true)])
        let text = String(decoding: PayloadFolderID.canonicalList(files), as: UTF8.self)
        #expect(text == "a/x\t\(digest("1"))\tx\nb\t\(digest("2"))\t-\n")
    }

    @Test func fingerprintIsTheSHA256PrefixOfTheCanonicalList() throws {
        let files = try records([("bin/php", "1", true)])
        let expected = FileDigest.hexSHA256(of: Data("bin/php\t\(digest("1"))\tx\n".utf8)).prefix(16)
        #expect(PayloadFolderID.make(payloadID: "php-8.5.11-arm64", files: files) == "php-8.5.11-arm64-\(expected)")
    }

    @Test func aChangedHashOrModeGivesANewFolder() throws {
        let base = PayloadFolderID.make(payloadID: "p", files: try records([("bin/php", "1", true)]))
        #expect(base != PayloadFolderID.make(payloadID: "p", files: try records([("bin/php", "2", true)])))
        #expect(base != PayloadFolderID.make(payloadID: "p", files: try records([("bin/php", "1", false)])))
        #expect(base == PayloadFolderID.make(payloadID: "p", files: try records([("bin/php", "1", true)])))
    }

    private func records(_ items: [(String, Character, Bool)]) throws -> [RelativePath: PayloadFileRecord] {
        var result: [RelativePath: PayloadFileRecord] = [:]
        for (path, hash, executable) in items {
            result[try #require(RelativePath(path))] = PayloadFileRecord(sha256: digest(hash), executable: executable)
        }
        return result
    }
}
