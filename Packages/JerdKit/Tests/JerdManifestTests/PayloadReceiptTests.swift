import Foundation
import JerdFoundation
import JerdManifest
import Testing

@Suite struct PayloadReceiptTests {
    @Test func receiptRoundTripsWithSortedPrettyKeys() throws {
        let receipt = try PayloadSample.receipt()
        let data = try receipt.encoded()
        #expect(try PayloadReceipt.decode(data) == receipt)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\n"))
        #expect(
            text.range(of: "\"archiveSHA256\"")?.lowerBound ?? text.endIndex
                < text.range(of: "\"files\"")?.lowerBound ?? text.startIndex)
        #expect(!text.contains("signing"))
    }

    @Test func signingRecordRoundTripsAndKeepsTheArchiveIdentity() throws {
        let receipt = try PayloadSample.receipt()
        let signing = PayloadSigning(teamID: "4L4SS26L9J", sourceReceiptSHA256: digest("c"))
        var files = receipt.fileRecords
        files[try #require(RelativePath("bin/php"))] = PayloadFileRecord(sha256: digest("9"), executable: true)
        let signed = receipt.replacingFiles(files, signing: signing)
        #expect(signed.archiveSHA256 == receipt.archiveSHA256 && signed.id == receipt.id)
        #expect(try PayloadReceipt.decode(signed.encoded()).signing == signing)
        #expect(signed.folderID != receipt.folderID)
    }

    @Test func folderIDIsThePayloadIDAndAFingerprintOfTheFiles() throws {
        let receipt = try PayloadSample.receipt()
        let prefix = "php-8.5.11-arm64-"
        #expect(receipt.folderID.hasPrefix(prefix))
        #expect(receipt.folderID.count == prefix.count + PayloadFolderID.fingerprintLength)
        #expect(PayloadIdentifier.isValid(receipt.folderID))
    }

    @Test(arguments: [
        ("schemaVersion", "2", "The payload receipt has an unsupported format version."),
        ("id", "\"../escape\"", "The payload receipt has an invalid identity."),
        ("version", "\"8.5-beta\"", "The payload receipt has an invalid identity."),
        ("releaseVersion", "\"nightly\"", "The payload receipt has an invalid identity."),
        ("archiveSHA256", "\"x\"", "The payload receipt has an invalid identity."),
        ("files", "{}", "The payload receipt has an invalid file list."),
        (
            "files", "{\"/abs\": {\"sha256\": \"\(digest("a"))\", \"executable\": true}}",
            "The payload receipt has an invalid file list."
        ),
        ("executable", "\"LICENSE\"", "The payload receipt does not record its executable: LICENSE."),
        (
            "signing", "{\"teamID\": \"short\", \"sourceReceiptSHA256\": \"\(digest("a"))\"}",
            "The payload receipt has an invalid signing record."
        ),
    ])
    func receiptsThatBreakARuleAreRefused(_ key: String, _ json: String, _ message: String) throws {
        var object = try #require(
            try JSONSerialization.jsonObject(with: PayloadSample.receipt().encoded()) as? [String: Any])
        object[key] = try JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: JerdError.invalid(message)) { try PayloadReceipt.decode(data) }
    }

    @Test func phpScriptsNeedNoExecutableFlagButNativeExecutablesDo() throws {
        let phar = try #require(RelativePath("composer.phar"))
        let files = [phar: PayloadFileRecord(sha256: digest("1"), executable: false)]
        func receipt(_ kind: RuntimeKind) -> PayloadReceipt {
            PayloadReceipt(
                id: "x-1.0.0", kind: kind, version: "1.0.0", releaseVersion: "1.0.0", architecture: .arm64,
                archiveSHA256: digest("a"), executable: phar, secondaryExecutable: nil, files: files)
        }
        try receipt(.composer).validate()
        #expect(throws: JerdError.self) { try receipt(.caddy).validate() }
    }

    @Test func receiptCannotListItself() throws {
        var files = try PayloadSample.receipt().fileRecords
        files[try #require(RelativePath(PayloadReceipt.fileName))] = PayloadFileRecord(
            sha256: digest("1"), executable: false)
        let receipt = try PayloadSample.receipt().replacingFiles(files, signing: nil)
        #expect(throws: JerdError.invalid("The payload receipt has an invalid file list.")) { try receipt.validate() }
    }

    @Test func unreadableReceiptsAreRefusedWithAReason() {
        #expect(throws: JerdError.invalid("The payload receipt is too large.")) {
            try PayloadReceipt.decode(Data(count: PayloadReceipt.sizeLimit + 1))
        }
        #expect(throws: JerdError.self) { try PayloadReceipt.decode(Data("{}".utf8)) }
    }
}

/// A small valid payload receipt.
enum PayloadSample {
    static func receipt() throws -> PayloadReceipt {
        let php = try #require(RelativePath("bin/php"))
        let license = try #require(RelativePath("LICENSE"))
        return PayloadReceipt(
            id: "php-8.5.11-arm64", kind: .php, version: "8.5.11", releaseVersion: "8.5.11", architecture: .arm64,
            archiveSHA256: digest("a"), executable: php, secondaryExecutable: nil,
            files: [
                php: PayloadFileRecord(sha256: digest("1"), executable: true),
                license: PayloadFileRecord(sha256: digest("2"), executable: false),
            ])
    }
}
