import Foundation
import JerdFoundation
import JerdManifest
import JerdTestSupport
import Testing

@Suite("Support receipts")
struct SupportReceiptTests {
    static let source = PinnedSupportSource(
        version: "5.8.4",
        archive: PinnedArchive(
            url: URL(string: "https://github.com/tukaani-project/xz/releases/download/v5.8.4/xz-5.8.4.tar.gz")!,
            size: 2_799_797, sha256: "0014c7886930454fe8bd4228665b51af55eeae560ea135c9c4cd33f55b2591d9"))

    static func receipt(files: [String: String], signing: PayloadSigning? = nil) -> SupportReceipt {
        SupportReceipt(
            name: "xz", version: "5.8.4", archiveSHA256: source.archive.sha256, deploymentTarget: "14.0", files: files,
            signing: signing)
    }

    @Test("The receipt that ./dev runtimes prepare wrote before still reads and matches its pin")
    func earlierReceiptReads() throws {
        let receipt = try SupportReceipt.decode(try Fixture.data("support-receipt-xz.json"))
        #expect(receipt.name == "xz" && receipt.signing == nil)
        #expect(Set(receipt.files.keys) == ["liblzma.5.dylib", "XZ-LICENSE.txt"])
        #expect(receipt.matches(Self.source, deploymentTarget: "14.0"))
        #expect(receipt.matches(Self.source))
        #expect(!receipt.matches(Self.source, deploymentTarget: "15.0"))
        // The encoding is the one that the tool wrote: pretty, sorted keys, and a final newline.
        #expect(try receipt.encoded() == (try Fixture.data("support-receipt-xz.json")))
    }

    @Test("Another release of the source does not match")
    func anotherReleaseDoesNotMatch() {
        let other = PinnedSupportSource(
            version: "5.8.5",
            archive: PinnedArchive(url: Self.source.archive.url, size: 1, sha256: digest("f")))
        #expect(!Self.receipt(files: ["a": digest("a")]).matches(other))
    }

    @Test("A signed receipt keeps its signing record and omits it when absent")
    func signingRecordRoundTrips() throws {
        let signed = Self.receipt(
            files: ["liblzma.5.dylib": digest("b")],
            signing: PayloadSigning(teamID: "ABCDE12345", sourceReceiptSHA256: digest("c")))
        #expect(try SupportReceipt.decode(try signed.encoded()) == signed)
        let plain = String(decoding: try Self.receipt(files: ["a": digest("a")]).encoded(), as: UTF8.self)
        #expect(!plain.contains("signing"))
        let bad = Self.receipt(
            files: ["a": digest("a")], signing: PayloadSigning(teamID: "short", sourceReceiptSHA256: digest("c")))
        #expect(throws: JerdError.self) { try bad.validate() }
    }

    @Test("Paths, hidden names, the receipt name, bad digests, and empty lists are refused")
    func fileListRulesHold() {
        let lists: [[String: String]] = [
            ["lib/liblzma.5.dylib": digest("b")], [".DS_Store": digest("b")], [SupportReceipt.fileName: digest("b")],
            ["liblzma.5.dylib": "short"], [:],
        ]
        for files in lists {
            #expect(throws: JerdError.self, "\(files)") { try Self.receipt(files: files).validate() }
        }
    }

    @Test("Verify accepts exactly the recorded files and names the first difference")
    func verifyChecksEveryFile() throws {
        let folder = try TemporaryDirectory("support-receipt")
        defer { folder.remove() }
        _ = try folder.file("xz/liblzma.5.dylib", "lzma")
        _ = try folder.file("xz/XZ-LICENSE.txt", "0BSD")
        let receipt = Self.receipt(files: [
            "liblzma.5.dylib": FileDigest.hexSHA256(of: Data("lzma".utf8)),
            "XZ-LICENSE.txt": FileDigest.hexSHA256(of: Data("0BSD".utf8)),
        ])
        _ = try folder.file("xz/\(SupportReceipt.fileName)", try receipt.encoded())
        let xz = folder.path("xz")
        try receipt.verify(in: xz)
        #expect(try SupportReceipt.read(from: xz) == receipt)
        #expect(try SupportReceipt.read(from: folder.path("none")) == nil)

        _ = try folder.file("xz/extra", "x")
        #expect(throws: JerdError.invalid("The xz support folder has other files than its receipt.")) {
            try receipt.verify(in: xz)
        }
        try FileManager.default.removeItem(at: folder.path("xz/extra"))
        _ = try folder.file("xz/liblzma.5.dylib", "changed")
        #expect(throws: JerdError.invalid("The xz support file liblzma.5.dylib changed.")) {
            try receipt.verify(in: xz)
        }
        // A link is not a regular file, also when its target has the recorded digest.
        try FileManager.default.removeItem(at: folder.path("xz/liblzma.5.dylib"))
        _ = try folder.file("target", "lzma")
        try FileManager.default.createSymbolicLink(
            at: folder.path("xz/liblzma.5.dylib"), withDestinationURL: folder.path("target"))
        #expect(throws: JerdError.self) { try receipt.verify(in: xz) }
    }
}
