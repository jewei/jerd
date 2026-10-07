import Darwin
import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

/// An earlier copy of Jerd installed MySQL from its bundle; this copy installs MySQL on demand.
@Suite struct OnDemandReuseTests {
    private static let files: [BundleBuilder.File] = [.init(path: "bin/mysqld", text: "mysqld", executable: true)]

    /// A bundle whose MySQL pin is embedded (`embedded == nil`) or installs on demand.
    private func bundle(_ folder: TemporaryFolder, name: String, embedded: Bool?) throws -> URL {
        var builder = BundleBuilder(root: folder.path(name))
        try builder.add(.mysql, id: "mysql-8.4.11-arm64", version: "8.4.11", files: Self.files, embedded: embedded)
        try builder.writeCatalog()
        return folder.path(name)
    }

    private func layout(_ folder: TemporaryFolder) -> DataLayout { DataLayout(root: folder.path("data")) }

    /// Installs the embedded MySQL as an earlier copy did, and returns its folder.
    private func installEarlierCopy(_ folder: TemporaryFolder) async throws -> URL {
        let earlier = BundledRuntimeBootstrap(
            resources: try bundle(folder, name: "earlier", embedded: nil), layout: layout(folder), architecture: .arm64)
        return try #require(try await earlier.installDatabases().first).directory
    }

    private func onDemand(_ folder: TemporaryFolder) throws -> OnDemandRuntimes {
        OnDemandRuntimes(resources: try bundle(folder, name: "current", embedded: false), architecture: .arm64)
    }

    @Test func verifiedPayloadOfAnEarlierCopyIsReused() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let installed = try await installEarlierCopy(folder)
        let reusable = try await onDemand(folder).reusablePayload(for: .mysql, layout: layout(folder))
        #expect(
            reusable
                == ReusablePayload(
                    id: installed.lastPathComponent, kind: .mysql, version: "8.4.11", directory: installed))
    }

    @Test func rustFSThatAnEarlierCopyEmbeddedIsReusedFromStorageRuntimes() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        func rustfs(_ name: String, embedded: Bool?) throws -> URL {
            var builder = BundleBuilder(root: folder.path(name))
            try builder.add(
                .rustfs, id: "rustfs-1.0.0-arm64", version: "1.0.0",
                files: [.init(path: "rustfs", text: "rustfs", executable: true)], embedded: embedded)
            try builder.writeCatalog()
            return folder.path(name)
        }
        let earlier = BundledRuntimeBootstrap(
            resources: try rustfs("earlier", embedded: nil), layout: layout(folder), architecture: .arm64)
        let installed = try #require(try await earlier.installStorage()).directory
        #expect(installed.deletingLastPathComponent().lastPathComponent == "storage-runtimes")
        let current = OnDemandRuntimes(resources: try rustfs("current", embedded: false), architecture: .arm64)
        let reusable = try await current.reusablePayload(for: .rustfs, layout: layout(folder))
        #expect(reusable?.directory == installed && reusable?.version == "1.0.0" && reusable?.kind == .rustfs)
    }

    /// A bundle with only the Mailpit pin, embedded (`nil`) or on demand.
    private func mailBundle(_ folder: TemporaryFolder, name: String, embedded: Bool?) throws -> URL {
        var builder = BundleBuilder(root: folder.path(name))
        try builder.add(
            .mailpit, id: "mailpit-1.31.3-arm64", version: "1.31.3",
            files: [.init(path: "mailpit", text: "mailpit", executable: true)], embedded: embedded)
        try builder.writeCatalog()
        return folder.path(name)
    }

    @Test func mailpitThatAnEarlierCopyEmbeddedIsReusedFromMailRuntimes() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let earlier = BundledRuntimeBootstrap(
            resources: try mailBundle(folder, name: "earlier", embedded: nil), layout: layout(folder),
            architecture: .arm64)
        let installed = try #require(try await earlier.installMail()).directory
        #expect(installed.deletingLastPathComponent().lastPathComponent == "mail-runtimes")
        let current = OnDemandRuntimes(
            resources: try mailBundle(folder, name: "current", embedded: false), architecture: .arm64)
        let reusable = try await current.reusablePayload(for: .mailpit, layout: layout(folder))
        #expect(reusable?.directory == installed && reusable?.version == "1.31.3" && reusable?.kind == .mailpit)
        #expect(try await current.hasReusablePayload(for: .mailpit, layout: layout(folder)))
    }

    /// The oldest copies wrote `mail-runtimes/<pin ID>/receipt.json` with plain file digests.
    @Test func legacyMailpitWithThePinnedDigestIsReused() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let legacy = folder.path("data/mail-runtimes/mailpit-1.31.3-arm64")
        try OwnedDirectory.create(legacy)
        try AtomicFile.write(Data("mailpit".utf8), to: legacy.appendingPathComponent("mailpit"))
        chmod(legacy.appendingPathComponent("mailpit").path, 0o700)
        let receipt = """
            {"archiveSHA256": "\(digest("c"))", "schemaVersion": 1,
             "files": {"mailpit": "\(FileDigest.hexSHA256(of: Data("mailpit".utf8)))"}}
            """
        try AtomicFile.write(Data(receipt.utf8), to: legacy.appendingPathComponent("receipt.json"))
        let current = OnDemandRuntimes(
            resources: try mailBundle(folder, name: "current", embedded: false), architecture: .arm64)
        let reusable = try await current.reusablePayload(for: .mailpit, layout: layout(folder))
        #expect(reusable?.id == "mailpit-1.31.3-arm64" && reusable?.version == "1.31.3")
        #expect(reusable?.directory.standardizedFileURL == legacy.standardizedFileURL)
    }

    @Test func changedPayloadIsNotReusedAndStaysAsItIs() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let installed = try await installEarlierCopy(folder)
        let binary = installed.appendingPathComponent("bin/mysqld")
        try AtomicFile.write(Data("changed".utf8), to: binary)
        #expect(try await onDemand(folder).reusablePayload(for: .mysql, layout: layout(folder)) == nil)
        // The cheap probe for the dialog reads receipts only; the install still refuses the folder.
        #expect(try await onDemand(folder).hasReusablePayload(for: .mysql, layout: layout(folder)))
        #expect(try Data(contentsOf: binary) == Data("changed".utf8))
    }

    @Test func legacyPayloadWithThePinnedDigestIsReused() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let legacy = folder.path("data/database-runtimes/mysql-8.4.11-arm64")
        try OwnedDirectory.create(legacy.appendingPathComponent("bin"))
        try AtomicFile.write(Data("mysqld".utf8), to: legacy.appendingPathComponent("bin/mysqld"))
        chmod(legacy.appendingPathComponent("bin/mysqld").path, 0o700)
        let receipt = """
            {"archiveSHA256": "\(digest("c"))", "schemaVersion": 1,
             "files": {"bin/mysqld": {"executable": true, "sha256": "\(FileDigest.hexSHA256(of: Data("mysqld".utf8)))"}}}
            """
        try AtomicFile.write(Data(receipt.utf8), to: legacy.appendingPathComponent("jerd-receipt.json"))
        let reusable = try await onDemand(folder).reusablePayload(for: .mysql, layout: layout(folder))
        #expect(reusable?.id == "mysql-8.4.11-arm64" && reusable?.version == "8.4.11")
        #expect(reusable?.directory.standardizedFileURL == legacy.standardizedFileURL)
    }

    @Test func linkedGroupFolderIsNeverFollowed() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        // Another data root holds a valid earlier payload; this root links its group folder there.
        let other = DataLayout(root: folder.path("other"))
        let earlier = BundledRuntimeBootstrap(
            resources: try bundle(folder, name: "earlier", embedded: nil), layout: other, architecture: .arm64)
        _ = try await earlier.installDatabases()
        try OwnedDirectory.create(folder.path("data"))
        try FileManager.default.createSymbolicLink(
            at: folder.path("data/database-runtimes"), withDestinationURL: other.runtimes.databaseRuntimesDirectory)
        #expect(try await onDemand(folder).reusablePayload(for: .mysql, layout: layout(folder)) == nil)
    }

    @Test func nothingInstalledMeansNothingToReuse() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        #expect(try await onDemand(folder).reusablePayload(for: .mysql, layout: layout(folder)) == nil)
        #expect(try await onDemand(folder).reusablePayload(for: .redis, layout: layout(folder)) == nil)
    }

    @Test func downloadProgressNamesTheBytesOfTheExactSize() {
        let title = "MySQL 8.4.11"
        #expect(
            RuntimePipeline.downloadMessage(title, fraction: 0, size: .exact(167_977_240)) == "Downloading \(title)…")
        #expect(
            RuntimePipeline.downloadMessage(title, fraction: 0.42, size: .exact(167_977_240))
                == "Downloading \(title)… 70.6\u{00A0}MB of 168\u{00A0}MB")
        #expect(RuntimePipeline.downloadMessage(title, fraction: 0.5, size: .atMost(1_000)) == "Downloading \(title)…")
    }

    @Test func requiredSpaceIsTheDownloadAndTheInstalledCopy() {
        let release = RuntimeRelease(
            kind: .mysql, version: "8.4.11",
            artifact: .archive(URL(fileURLWithPath: "/x"), size: .exact(100)), archiveSHA256: digest("c"),
            releasePage: URL(fileURLWithPath: "/x"), installedSize: 300)
        #expect(release.requiredSpace == 400)
        #expect(ByteText.format(122_517_005) == "122.5\u{00A0}MB")
    }
}
