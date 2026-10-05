import Foundation
import JerdFoundation
import JerdManifest
import Testing

@Suite struct BuildReceiptTests {
    @Test func goldenCaddyReceiptFromAnInstalledCopyDecodes() throws {
        let receipt = try BuildReceipt.decode(Fixture.data("update-receipt-caddy.json"))
        #expect(receipt.kind == .caddy)
        #expect(receipt.version == "2.11.6" && receipt.releaseVersion == "2.11.6")
        #expect(receipt.executablePath?.string == "caddy")
        #expect(receipt.secondaryExecutablePath == nil)
        #expect(Set(receipt.fileHashes.keys.map(\.string)) == ["caddy", "LICENSE", "README.md"])
        #expect(receipt.matchesFolderName("caddy-2.11.6-arm64", architecture: .arm64))
    }

    @Test func goldenPHPReceiptKeepsItsFPMExecutable() throws {
        let receipt = try BuildReceipt.decode(Fixture.data("update-receipt-php.json"))
        #expect(receipt.kind == .php)
        #expect(receipt.executable == "php-native-8.4")
        #expect(receipt.secondaryExecutable == "php-native-fpm-8.4")
        #expect(receipt.files.count == 4)
    }

    @Test func encodingUsesTheCompactFormatAndOmitsAMissingSecondaryExecutable() throws {
        let receipt = try sample(secondary: nil)
        let data = try receipt.encoded()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(
            Set(object.keys) == [
                "schemaVersion", "kind", "version", "releaseVersion", "archiveSHA256", "executable", "files",
            ])
        #expect(!String(decoding: data, as: UTF8.self).contains("\n"))
        #expect(try BuildReceipt.decode(data) == receipt)
    }

    @Test func folderNamesHaveTheCurrentAndTheLegacyForm() throws {
        let receipt = try sample(secondary: nil)
        let current = BuildReceipt.folderName(
            kind: .php, releaseVersion: "8.5.11", architecture: .arm64, archiveSHA256: digest("a"))
        #expect(current == "php-8.5.11-arm64-\(digest("a"))")
        #expect(receipt.matchesFolderName(current, architecture: .arm64))
        #expect(receipt.matchesFolderName("php-8.5.11-arm64", architecture: .arm64))
        #expect(!receipt.matchesFolderName("php-8.5.11-x86_64", architecture: .arm64))
        #expect(!receipt.matchesFolderName("php-8.5.10-arm64", architecture: .arm64))
        #expect(!receipt.matchesFolderName("php-8.5.11-arm64-\(digest("b"))", architecture: .arm64))
    }

    /// Each case replaces one key with a JSON value that breaks one rule of I14.
    @Test(arguments: [
        ("schemaVersion", "2"), ("version", "\"8.5.0RC1\""), ("releaseVersion", "\"latest\""),
        ("archiveSHA256", "\"ABC\""), ("executable", "\"missing\""), ("secondaryExecutable", "\"missing\""),
        ("files", "{}"), ("files", "{\"../php\": \"\(digest("a"))\"}"), ("files", "{\"php\": \"not hex\"}"),
        ("kind", "\"java\""),
    ])
    func receiptsThatBreakARuleAreRefused(_ key: String, _ json: String) throws {
        var object = try #require(
            try JSONSerialization.jsonObject(with: sample(secondary: "php-fpm").encoded()) as? [String: Any])
        object[key] = try JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: JerdError.invalid("The update receipt is invalid. Existing files were preserved.")) {
            try BuildReceipt.decode(data)
        }
    }

    @Test func oversizedAndNonJSONReceiptsAreRefused() {
        #expect(throws: JerdError.invalid("The update receipt is too large.")) {
            try BuildReceipt.decode(Data(count: BuildReceipt.sizeLimit))
        }
        #expect(throws: JerdError.invalid("The update receipt is invalid. Existing files were preserved.")) {
            try BuildReceipt.decode(Data("not json".utf8))
        }
    }

    private func sample(secondary: String?) throws -> BuildReceipt {
        var files = [try #require(RelativePath("php")): digest("1")]
        if let secondary { files[try #require(RelativePath(secondary))] = digest("2") }
        return BuildReceipt(
            kind: .php, version: "8.5.11", releaseVersion: "8.5.11", archiveSHA256: digest("a"),
            executable: try #require(RelativePath("php")), secondaryExecutable: secondary.flatMap { RelativePath($0) },
            files: files)
    }
}
