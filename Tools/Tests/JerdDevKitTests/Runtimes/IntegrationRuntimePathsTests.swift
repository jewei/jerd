import Foundation
import Testing

@testable import JerdDevKit

@Suite("Integration runtime paths")
struct IntegrationRuntimePathsTests {
    private func paths(_ root: URL) throws -> IntegrationRuntimePaths {
        IntegrationRuntimePaths(
            inventory: PayloadInventory(root: root.appending(path: "payloads"), catalog: try PayloadFixtures.catalog()),
            indexRoot: root.appending(path: "integration"))
    }

    @Test("Web paths come from the PHP and Caddy receipts, not from file names in the tool")
    func webPathsFromReceipts() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let php = try PayloadFixtures.writePayload(.php, in: root.appending(path: "payloads"))
        let caddy = try PayloadFixtures.writePayload(.caddy, in: root.appending(path: "payloads"))
        let variables = try paths(root).variables(for: .web)
        #expect(variables["JERD_PHP_CLI"] == php.appending(path: "bin/php").path)
        #expect(variables["JERD_PHP_FPM"] == php.appending(path: "sbin/php-fpm").path)
        #expect(variables["JERD_CADDY"] == caddy.appending(path: "bin/caddy").path)
    }

    @Test("Mail and storage paths are the payload folders")
    func serviceFolders() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let mail = try PayloadFixtures.writePayload(.mailpit, in: root.appending(path: "payloads"))
        let storage = try PayloadFixtures.writePayload(.rustfs, in: root.appending(path: "payloads"))
        #expect(try paths(root).variables(for: .mail) == ["JERD_MAIL_RUNTIME": mail.path])
        #expect(try paths(root).variables(for: .storage) == ["JERD_STORAGE_RUNTIME": storage.path])
    }

    @Test("The database index lists each engine and links to the unchanged payload")
    func databaseIndex() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try PayloadFixtures.writePayloads([.database], in: root.appending(path: "payloads"))
        let folder = URL(filePath: try #require(try paths(root).variables(for: .database)["JERD_DATABASE_RUNTIMES"]))
        let index = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "pins.json")))
        let artifacts = try #require((index as? [String: Any])?["artifacts"] as? [[String: String]])
        #expect(artifacts.map { $0["engine"] } == ["mysql", "postgresql", "redis"])
        let mysql = try PayloadFixtures.pin(.mysql).id
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: folder.appending(path: mysql).path)
        #expect(link.hasSuffix("payloads/database/\(mysql)"))
        _ = try paths(root).variables(for: .database)
    }

    @Test("A missing payload is a missing prerequisite with the prepare command")
    func missingPayload() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try paths(root).variables(for: .mail)
            Issue.record("Expected a failure.")
        } catch let failure as DevFailure {
            #expect(failure.status == .missingPrerequisite)
            #expect(failure.message.contains("./dev runtimes prepare mail"))
        }
    }

    @Test("A changed payload is never handed to the tests")
    func invalidPayload() throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try PayloadFixtures.writePayload(.mailpit, in: root.appending(path: "payloads"))
        try Data("changed".utf8).write(to: folder.appending(path: "bin/mailpit"))
        do {
            _ = try paths(root).variables(for: .mail)
            Issue.record("Expected a failure.")
        } catch let failure as DevFailure {
            #expect(failure.status == .checkFailed)
        }
    }
}
