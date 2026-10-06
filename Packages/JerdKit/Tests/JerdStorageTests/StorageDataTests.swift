import Foundation
import JerdFoundation
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdStorage

@Suite struct StorageDataTests {
    let directory: TemporaryDirectory
    let layout: StorageLayout
    let data: StorageData
    let runtime = StorageSettingsTests.runtime
    let other = StorageRuntime(id: "rustfs-2", version: "2.0.0", path: "/runtimes/rustfs-2")

    init() throws {
        directory = try TemporaryDirectory()
        layout = DataLayout(root: directory.path("Jerd")).storage
        try OwnedDirectory.create(layout.root)
        data = StorageData(layout: layout)
    }

    /// Simulates the first successful start: RustFS writes its format file, then Jerd the marker.
    private func initialize() throws -> StorageCredentials {
        let credentials = try data.prepare(for: runtime)
        try write(String(decoding: StorageHarness.format, as: UTF8.self), to: layout.formatFile)
        try data.markInitialized(runtime)
        return credentials
    }

    @Test func newDataGetsIdentityCredentialsAndRawKeyFiles() throws {
        defer { directory.remove() }
        let credentials = try data.prepare(for: runtime)
        #expect(try MarkerFile.read(StorageRuntime.self, from: layout.runtimeIdentityFile) == runtime)
        #expect(
            try JSONDecoder().decode(StorageCredentials.self, from: #require(contents(layout.credentialsFile)))
                == credentials)
        #expect(contents(layout.accessKeyFile) == Data(credentials.accessKey.utf8))
        #expect(contents(layout.secretKeyFile) == Data(credentials.secretKey.utf8))
        for file in [layout.credentialsFile, layout.accessKeyFile, layout.secretKeyFile] {
            #expect(mode(file) == 0o600)
        }
        #expect(mode(layout.dataDirectory) == 0o700)
        #expect(try data.prepare(for: runtime) == credentials)
    }

    @Test func theFilesOfOlderBuildsAreAcceptedAsTheyAre() throws {
        defer { directory.remove() }
        try OwnedDirectory.create(layout.dataDirectory)
        try AtomicFile.write(try golden("storage-credentials.json"), to: layout.credentialsFile)
        try AtomicFile.write(try golden("storage-runtime.json"), to: layout.runtimeIdentityFile)
        try AtomicFile.write(try golden("storage-initialized.json"), to: layout.initializedMarkerFile)
        try write(String(decoding: try golden("storage-format.json"), as: UTF8.self), to: layout.formatFile)
        try data.validate(for: runtime)
        #expect(try data.prepare(for: runtime) == StorageSettingsTests.credentials)
        #expect(contents(layout.credentialsFile) == (try golden("storage-credentials.json")))
        #expect(contents(layout.initializedMarkerFile) == (try golden("storage-initialized.json")))
    }

    /// Spec 3.4.6.d: after a successful start, a changed credential file fails the pure hash
    /// compare first, so the message names changed data, not invalid credentials.
    @Test func unreadableCredentialsOfInitializedDataAreReportedAsChangedData() throws {
        defer { directory.remove() }
        _ = try initialize()
        try AtomicFile.write(Data("not json".utf8), to: layout.credentialsFile)
        #expect(throws: StorageMessages.dataChanged) { try data.prepare(for: runtime) }
        #expect(throws: StorageMessages.dataChanged) { try data.validate(for: runtime) }
        #expect(contents(layout.credentialsFile) == Data("not json".utf8))
        try FileManager.default.removeItem(at: layout.credentialsFile)
        #expect(throws: StorageMessages.requiredFileInvalid) { try data.prepare(for: runtime) }
    }

    @Test func credentialBytesAreNeverEncodedAgainAndTheMarkerFollowsThem() throws {
        defer { directory.remove() }
        let reordered = Data(
            #"{"secretKey":"00112233445566778899AABBCCDDEEFF0011223344556677","accessKey":"JERD0123456789ABCDEF"}"#
                .utf8)
        try OwnedDirectory.create(layout.dataDirectory)
        try AtomicFile.write(reordered, to: layout.credentialsFile)
        try MarkerFile.write(runtime, to: layout.runtimeIdentityFile)
        try write(String(decoding: StorageHarness.format, as: UTF8.self), to: layout.formatFile)
        try data.markInitialized(runtime)
        #expect(try data.prepare(for: runtime) == StorageSettingsTests.credentials)
        try data.adopt(other)
        #expect(contents(layout.credentialsFile) == reordered)
        let marker = try MarkerFile.read(StorageInitializedMarker.self, from: layout.initializedMarkerFile)
        #expect(marker.runtime == other && marker.credentialsHash == FileDigest.hexSHA256(of: reordered))
        #expect(try data.prepare(for: other) == StorageSettingsTests.credentials)
    }

    @Test func changedFormatCredentialsOrRuntimeRefuseTheStartAndKeepTheFiles() throws {
        defer { directory.remove() }
        _ = try initialize()
        let credentials = try #require(contents(layout.credentialsFile))
        try write("{\"version\":\"2\"}", to: layout.formatFile)
        #expect(throws: StorageMessages.dataChanged) { try data.prepare(for: runtime) }
        #expect(throws: StorageMessages.dataChanged) { try data.validate(for: runtime) }
        try write(String(decoding: StorageHarness.format, as: UTF8.self), to: layout.formatFile)
        try data.validate(for: runtime)
        #expect(throws: StorageMessages.dataChanged) { try data.validate(for: other) }
        try AtomicFile.write(credentials + Data(" ".utf8), to: layout.credentialsFile)
        #expect(throws: StorageMessages.dataChanged) { try data.prepare(for: runtime) }
        try FileManager.default.removeItem(at: layout.formatFile)
        #expect(throws: StorageMessages.requiredFileInvalid) { try data.prepare(for: runtime) }
        #expect(contents(layout.credentialsFile) == credentials + Data(" ".utf8))
    }

    @Test func dataOfAnotherRuntimeOrWithoutAnIdentityIsNeverAdopted() throws {
        defer { directory.remove() }
        try write("object", to: layout.dataDirectory.appendingPathComponent("bucket/object"))
        #expect(throws: StorageMessages.untracked) { try data.validate(for: runtime) }
        #expect(throws: StorageMessages.untracked) { try data.prepare(for: runtime) }
        #expect(!exists(layout.credentialsFile) && !exists(layout.runtimeIdentityFile))
        try MarkerFile.write(other, to: layout.runtimeIdentityFile)
        #expect(throws: StorageMessages.identityMismatch) { try data.prepare(for: runtime) }
    }

    @Test func missingCredentialsForExistingDataAreNeverCreatedAgain() throws {
        defer { directory.remove() }
        _ = try data.prepare(for: runtime)
        try write("object", to: layout.dataDirectory.appendingPathComponent("bucket/object"))
        try FileManager.default.removeItem(at: layout.credentialsFile)
        #expect(throws: StorageMessages.credentialsMissing) { try data.prepare(for: runtime) }
        #expect(throws: StorageMessages.credentialsMissing) { try data.validate(for: runtime) }
        #expect(!exists(layout.credentialsFile))
    }

    @Test func invalidCredentialFilesArePreserved() throws {
        defer { directory.remove() }
        _ = try data.prepare(for: runtime)
        let bad = Data(#"{"accessKey":"short","secretKey":"x"}"#.utf8)
        try AtomicFile.write(bad, to: layout.credentialsFile)
        #expect(throws: StorageMessages.credentialsInvalid) { try data.prepare(for: runtime) }
        #expect(throws: StorageMessages.credentialsInvalid) { try data.credentials() }
        #expect(contents(layout.credentialsFile) == bad)
    }

    @Test func validationBeforeAnUpdateWritesNothing() throws {
        defer { directory.remove() }
        try data.validate(for: runtime)
        #expect(!exists(layout.dataDirectory) && !exists(layout.credentialsFile) && !exists(layout.runtimeIdentityFile))
        #expect(throws: StorageMessages.startOnce) { try data.credentials() }
    }

    @Test func adoptionMovesOnlyTheMarkersThatExist() throws {
        defer { directory.remove() }
        _ = try data.prepare(for: runtime)
        try data.adopt(other)
        #expect(try MarkerFile.read(StorageRuntime.self, from: layout.runtimeIdentityFile) == other)
        #expect(!exists(layout.initializedMarkerFile))
    }
}
