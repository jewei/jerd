import Foundation
import JerdFoundation
import JerdManifest
import Testing

@Suite struct LegacyPayloadReceiptTests {
    @Test(arguments: ["php", "caddy", "composer"])
    func goldenDevelopmentReceiptsDecode(_ name: String) throws {
        let receipt = try LegacyPayloadReceipt.decode(
            Fixture.data("development-receipt-\(name).json"), format: .development)
        #expect(receipt.executables == nil)
        #expect(!receipt.fileHashes.isEmpty)
    }

    @Test func goldenPHPReceiptListsTheFourBundledFiles() throws {
        let receipt = try LegacyPayloadReceipt.decode(
            Fixture.data("development-receipt-php.json"), format: .development)
        #expect(
            Set(receipt.fileHashes.keys.map(\.string)) == [
                "php-native-8.5", "php-native-fpm-8.5", "THIRD-PARTY-NOTICES.txt", "BUILD-INFO.txt",
            ])
        #expect(receipt.archiveSHA256 == "59761adfe93cf737282843ea1cbc74e2fef3dd86839554efd71c3dddb2b867dc")
    }

    @Test func goldenDatabaseReceiptKeepsExecutableFlags() throws {
        let receipt = try LegacyPayloadReceipt.decode(
            Fixture.data("database-receipt-mysql.json"), format: .database)
        let executables = try #require(receipt.executables)
        #expect(executables.contains(try #require(RelativePath("bin/mysqld"))))
        #expect(!executables.contains(try #require(RelativePath("LICENSE"))))
        #expect(receipt.archiveSHA256 == "b96e00493bc3499b9ffd7f08d65c5d64933af0383a8287d9873b64f94c2d6009")
    }

    @Test func goldenMailAndStorageReceiptsDecode() throws {
        let mail = try LegacyPayloadReceipt.decode(Fixture.data("mail-receipt.json"), format: .service)
        #expect(Set(mail.fileHashes.keys.map(\.string)) == ["mailpit", "LICENSE", "README.md"])
        let storage = try LegacyPayloadReceipt.decode(Fixture.data("storage-receipt.json"), format: .service)
        #expect(Set(storage.fileHashes.keys.map(\.string)) == ["rustfs", "LICENSE"])
        #expect(LegacyPayloadReceipt.Format.service.fileName == "receipt.json")
        #expect(LegacyPayloadReceipt.Format.database.fileName == "jerd-receipt.json")
    }

    @Test func aReceiptOfAnotherFormIsRefused() throws {
        #expect(throws: JerdError.self) {
            try LegacyPayloadReceipt.decode(Fixture.data("mail-receipt.json"), format: .development)
        }
        #expect(throws: JerdError.self) {
            try LegacyPayloadReceipt.decode(Fixture.data("database-receipt-mysql.json"), format: .service)
        }
    }

    @Test(arguments: [
        "{\"schemaVersion\": 2, \"archiveSHA256\": \"\(digest("a"))\", \"files\": {\"x\": \"\(digest("b"))\"}}",
        "{\"schemaVersion\": 1, \"archiveSHA256\": \"upstream\", \"files\": {\"x\": \"\(digest("b"))\"}}",
        "{\"schemaVersion\": 1, \"archiveSHA256\": \"\(digest("a"))\", \"files\": {}}",
        "{\"schemaVersion\": 1, \"archiveSHA256\": \"\(digest("a"))\", \"files\": {\"../x\": \"\(digest("b"))\"}}",
        "{\"schemaVersion\": 1, \"archiveSHA256\": \"\(digest("a"))\", \"files\": {\"x\": \"short\"}}",
    ])
    func serviceReceiptsThatBreakARuleAreRefused(_ json: String) {
        #expect(throws: JerdError.invalid("The installed runtime receipt is invalid. Existing files were preserved.")) {
            try LegacyPayloadReceipt.decode(Data(json.utf8), format: .service)
        }
    }
}
