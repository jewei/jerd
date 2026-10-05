import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@Suite struct ManagedExecutableVerifierTests {
    /// Writes a legacy development PHP folder whose receipt names the real file hash.
    private func legacyBundle(_ layout: DataLayout) throws -> URL {
        let build = layout.runtimes.developmentRuntimesDirectory.appendingPathComponent("php-php-8.5.11-arm64")
        try OwnedDirectory.create(build)
        let php = build.appendingPathComponent("php-native-8.5")
        try Data("php binary".utf8).write(to: php)
        let receipt: [String: Any] = [
            "schemaVersion": 1, "tag": "php-8.5.11", "archiveSHA256": digest("a"),
            "fileSHA256": ["php-native-8.5": try FileDigest.hexSHA256(of: php)],
            "publisherSignatureVerified": false,
        ]
        try AtomicFile.write(
            try JSONSerialization.data(withJSONObject: receipt), to: build.appendingPathComponent("jerd-receipt.json"))
        return php
    }

    @Test func legacyBundledPHPIsVerified() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        let php = try legacyBundle(layout)
        let verified = try ManagedExecutableVerifier(layout: layout).verifyPHP(php)
        #expect(verified.relativePath == "php-native-8.5")
        #expect(verified.build.lastPathComponent == "php-php-8.5.11-arm64")
    }

    @Test func changedExecutableFailsVerification() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        let php = try legacyBundle(layout)
        try Data("changed".utf8).write(to: php)
        #expect(throws: JerdError.invalid("The installed PHP executable failed verification.")) {
            try ManagedExecutableVerifier(layout: layout).verifyPHP(php)
        }
    }

    @Test func managedBuildMustBePHPAndNameTheExecutable() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        let build = layout.runtimes.managedRuntimesDirectory.appendingPathComponent("php-8.4.26-arm64")
        try OwnedDirectory.create(build)
        let cli = build.appendingPathComponent("php-native-8.4")
        try Data("cli".utf8).write(to: cli)
        let notes = build.appendingPathComponent("BUILD-INFO.txt")
        try Data("notes".utf8).write(to: notes)
        let receipt = BuildReceipt(
            kind: .php, version: "8.4.26", releaseVersion: "8.4.26", archiveSHA256: digest("a"),
            executable: try #require(RelativePath("php-native-8.4")), secondaryExecutable: nil,
            files: [
                try #require(RelativePath("php-native-8.4")): try FileDigest.hexSHA256(of: cli),
                try #require(RelativePath("BUILD-INFO.txt")): try FileDigest.hexSHA256(of: notes),
            ])
        try AtomicFile.write(try receipt.encoded(), to: build.appendingPathComponent("update-receipt.json"))
        let verifier = ManagedExecutableVerifier(layout: layout)
        #expect(try verifier.verifyPHP(cli).relativePath == "php-native-8.4")
        #expect(throws: JerdError.invalid("The installed PHP receipt does not match the selected executable.")) {
            try verifier.verifyPHP(notes)
        }
    }

    @Test func executableOutsideTheRuntimeFoldersIsNotManaged() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let other = try folder.write("php", to: "elsewhere/php")
        let layout = DataLayout(root: folder.path("data"))
        #expect(throws: JerdError.invalid("Select a managed Jerd PHP runtime before setting up its CLI command.")) {
            try ManagedExecutableVerifier(layout: layout).verifyPHP(other)
        }
        try OwnedDirectory.create(layout.runtimes.developmentRuntimesDirectory)
        let loose = layout.runtimes.developmentRuntimesDirectory.appendingPathComponent("php")
        try Data("php".utf8).write(to: loose)
        #expect(throws: JerdError.self) { try ManagedExecutableVerifier(layout: layout).verifyPHP(loose) }
    }
}
