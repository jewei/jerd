import Foundation
import Testing
@testable import JerdCore

struct BundledReleaseTests {
    private func fixture(_ root: URL, kind: String, installationID: String?) throws -> URL {
        let source = root.appendingPathComponent("source")
        let payload = source.appendingPathComponent("test-runtime")
        try PrivateFiles.directory(payload)
        let names = kind == "storage" ? ["rustfs", "LICENSE", "liblzma.5.dylib", "XZ-LICENSE.txt"] :
            kind == "mail" ? ["mailpit", "LICENSE", "README.md"] : ["bin/redis-server", "bin/redis-cli"]
        var files: [String: Any] = [:]
        for name in names {
            let file = payload.appendingPathComponent(name)
            try PrivateFiles.directory(file.deletingLastPathComponent())
            try PrivateFiles.write(Data("release payload \(name)".utf8), to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            let hash = try RuntimeDownload.digest(file)
            files[name] = kind == "database" ? ["sha256": hash, "executable": true] : hash
        }
        var entry: [String: Any] = ["schemaVersion": 1, "id": "test-runtime", "version": "1.0.0",
                                    "architecture": CPUArchitecture.current.rawValue, "sha256": "upstream"]
        if let installationID { entry["installationID"] = installationID }
        let receipt: [String: Any] = ["schemaVersion": 1, "archiveSHA256": "upstream", "files": files]
        let receiptName = kind == "database" ? "jerd-receipt.json" : "receipt.json"
        try PrivateFiles.write(JSONSerialization.data(withJSONObject: receipt), to: payload.appendingPathComponent(receiptName))
        if kind == "database" {
            entry["engine"] = "redis"
            let pins: [String: Any] = ["schemaVersion": 1, "architecture": CPUArchitecture.current.rawValue, "artifacts": [entry]]
            try PrivateFiles.write(JSONSerialization.data(withJSONObject: pins), to: source.appendingPathComponent("pins.json"))
        } else {
            try PrivateFiles.write(JSONSerialization.data(withJSONObject: entry), to: source.appendingPathComponent("pin.json"))
        }
        return source
    }

    private func install(_ kind: String, from source: URL, into target: URL) async throws -> String {
        if kind == "storage" { return try await BundledStorageRuntime().install(from: source, into: target).id }
        if kind == "mail" { return try await BundledMailRuntime().install(from: source, into: target).id }
        return try #require(await BundledDatabaseRuntimes().install(from: source, into: target).first).id
    }

    @Test(arguments: ["storage", "mail", "database"])
    func signedPayloadsPreservePreviousInstallationsAndCorruptFiles(_ kind: String) async throws {
        let root = try temporaryDirectory(" release payload")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixture(root, kind: kind, installationID: nil)
        let target = root.appendingPathComponent("installed")
        #expect(try await install(kind, from: source, into: target) == "test-runtime")
        let legacyFile = target.appendingPathComponent("test-runtime/" + (kind == "database" ? "bin/redis-server" : "LICENSE"))
        let legacy = try Data(contentsOf: legacyFile)
        _ = try fixture(root, kind: kind, installationID: "test-runtime-release-123")
        #expect(try await install(kind, from: source, into: target) == "test-runtime-release-123")
        #expect(try Data(contentsOf: legacyFile) == legacy)
        let installedFile = target.appendingPathComponent("test-runtime-release-123/" + (kind == "database" ? "bin/redis-server" : "LICENSE"))
        let corrupt = Data("preserve this corrupt file".utf8)
        try PrivateFiles.write(corrupt, to: installedFile)
        await #expect(throws: (any Error).self) { try await install(kind, from: source, into: target) }
        #expect(try Data(contentsOf: installedFile) == corrupt)
        #expect(try Data(contentsOf: legacyFile) == legacy)
    }

    @Test(arguments: ["storage", "mail", "database"])
    func installationIDCannotEscapeItsDirectory(_ kind: String) async throws {
        let root = try temporaryDirectory(" invalid release ID")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try fixture(root, kind: kind, installationID: "../escape")
        await #expect(throws: (any Error).self) {
            try await install(kind, from: source, into: root.appendingPathComponent("installed"))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escape").path))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["JERD_RELEASE_RESOURCES"] != nil,
                   "Select signed release resources to test installation."))
    func signedReleaseInstallsIntoPrivateDirectories() async throws {
        let source = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["JERD_RELEASE_RESOURCES"]))
        let root = try temporaryDirectory(" signed release bootstrap")
        defer { try? FileManager.default.removeItem(at: root) }
        let web = try await BundledRuntimes().install(from: source.appendingPathComponent("DevelopmentRuntimes"), into: root.appendingPathComponent("web"))
        #expect(web.0.cliPath.contains("-release-"))
        let databases = try await BundledDatabaseRuntimes().install(from: source.appendingPathComponent("DatabaseRuntimes"), into: root.appendingPathComponent("database"))
        #expect(databases.count == 3 && databases.allSatisfy { $0.id.contains("-release-") })
        let mail = try await BundledMailRuntime().install(from: source.appendingPathComponent("MailRuntime"), into: root.appendingPathComponent("mail"))
        #expect(mail.id.contains("-release-"))
        let storage = try await BundledStorageRuntime().install(from: source.appendingPathComponent("StorageRuntime"), into: root.appendingPathComponent("storage"))
        #expect(storage.id.contains("-release-"))
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: storage.path).appendingPathComponent("liblzma.5.dylib").path))
    }
}
