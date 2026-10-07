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

    @Test func changedPayloadIsNotReusedAndStaysAsItIs() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let installed = try await installEarlierCopy(folder)
        let binary = installed.appendingPathComponent("bin/mysqld")
        try AtomicFile.write(Data("changed".utf8), to: binary)
        #expect(try await onDemand(folder).reusablePayload(for: .mysql, layout: layout(folder)) == nil)
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
