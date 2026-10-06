import Foundation
import JerdDatabases
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@testable import JerdLive

@Suite("Bundled runtime mapping")
struct BundledRuntimeMappingTests {
    static func payload(_ kind: RuntimeKind, executable: String, folder: String) throws -> InstalledPayload {
        let receipt = PayloadReceipt(
            id: "\(kind.rawValue)-pin", kind: kind, version: "1.2.3", releaseVersion: "1.2.3", architecture: .arm64,
            archiveSHA256: String(repeating: "a", count: 64), executable: try #require(RelativePath(executable)),
            secondaryExecutable: nil, files: [:])
        return InstalledPayload(receipt: receipt, directory: URL(fileURLWithPath: "/data/\(folder)", isDirectory: true))
    }

    @Test(arguments: [RuntimeKind.mysql, .postgresql, .redis])
    func aDatabasePayloadKeepsItsFolderAsIDAndPath(kind: RuntimeKind) throws {
        let runtime = try BundledRuntimeMapping.database(Self.payload(kind, executable: "bin/server", folder: "db-1"))

        #expect(runtime.id == "db-1")
        #expect(runtime.path == "/data/db-1")
        #expect(runtime.version == "1.2.3")
        #expect(BundledRuntimeMapping.kind(of: runtime.engine) == kind)
    }

    @Test func mailAndStoragePayloadsBecomeTheirRuntimes() throws {
        let mail = try BundledRuntimeMapping.mail(Self.payload(.mailpit, executable: "mailpit", folder: "mail-1"))
        let storage = try BundledRuntimeMapping.storage(Self.payload(.rustfs, executable: "rustfs", folder: "rustfs-1"))

        #expect(mail.id == "mail-1")
        #expect(mail.executable.path == "/data/mail-1/mailpit")
        #expect(storage.id == "rustfs-1")
        #expect(storage.executable.path == "/data/rustfs-1/rustfs")
    }

    @Test func aPayloadOfAnotherKindIsRefused() throws {
        let php = try Self.payload(.php, executable: "php", folder: "php-1")

        #expect(throws: JerdError.self) { try BundledRuntimeMapping.database(php) }
        #expect(throws: JerdError.self) { try BundledRuntimeMapping.mail(php) }
        #expect(throws: JerdError.self) { try BundledRuntimeMapping.storage(php) }
    }

    @Test func onlyDatabaseKindsHaveAnEngine() {
        for kind in RuntimeKind.allCases {
            let engine = BundledRuntimeMapping.engine(of: kind)
            #expect((engine != nil) == [.mysql, .postgresql, .redis].contains(kind))
            if let engine { #expect(BundledRuntimeMapping.kind(of: engine) == kind) }
        }
    }

    @Test func registeredKindsComeFromTheSavedRuntimes() {
        let configuration = DatabaseConfiguration(runtimes: [
            DatabaseRuntime(id: "a", engine: .redis, version: "8", path: "/r"),
            DatabaseRuntime(id: "b", engine: .redis, version: "9", path: "/s"),
        ])

        #expect(BundledRuntimeMapping.registeredKinds(configuration) == [.redis])
    }
}
