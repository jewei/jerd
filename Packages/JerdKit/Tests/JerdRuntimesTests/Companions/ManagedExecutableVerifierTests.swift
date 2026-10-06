import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@Suite struct ManagedExecutableVerifierTests {
    private static let mismatch = JerdError.invalid("The installed PHP receipt does not match the selected executable.")
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

    /// RT-5: only the file that the receipt names as the CLI executable passes, for every receipt form.
    @Test func bundledPayloadAcceptsOnlyItsCLIExecutable() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var builder = BundleBuilder(root: folder.path("bundle"))
        try builder.addDevelopment(phpVersion: "8.6.1", phpExtras: [.init(path: "BUILD-INFO.txt", text: "notes")])
        try builder.writeCatalog()
        let layout = DataLayout(root: folder.path("data"))
        let bootstrap = BundledRuntimeBootstrap(resources: folder.path("bundle"), layout: layout, architecture: .arm64)
        let php = try await bootstrap.installDevelopment().php
        let verifier = ManagedExecutableVerifier(layout: layout)
        #expect(try verifier.verifyPHP(php.executable).relativePath == "php-native-8.6")
        for other in [try #require(php.secondaryExecutable), php.directory.appendingPathComponent("BUILD-INFO.txt")] {
            #expect(throws: Self.mismatch) { try verifier.verifyPHP(other) }
        }
    }

    @Test func managedBuildRefusesItsFPMExecutable() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        let build = layout.runtimes.managedRuntimesDirectory.appendingPathComponent("php-8.4.26-arm64")
        let cli = try folder.write("cli", to: "runtime-updates/php-8.4.26-arm64/php-native-8.4")
        let fpm = try folder.write("fpm", to: "runtime-updates/php-8.4.26-arm64/php-native-fpm-8.4")
        #expect(build.appendingPathComponent("php-native-8.4") == cli)
        let receipt = BuildReceipt(
            kind: .php, version: "8.4.26", releaseVersion: "8.4.26", archiveSHA256: digest("a"),
            executable: try #require(RelativePath("php-native-8.4")),
            secondaryExecutable: RelativePath("php-native-fpm-8.4"),
            files: [
                try #require(RelativePath("php-native-8.4")): try FileDigest.hexSHA256(of: cli),
                try #require(RelativePath("php-native-fpm-8.4")): try FileDigest.hexSHA256(of: fpm),
            ])
        try AtomicFile.write(try receipt.encoded(), to: build.appendingPathComponent("update-receipt.json"))
        let verifier = ManagedExecutableVerifier(layout: layout)
        #expect(try verifier.verifyPHP(cli).relativePath == "php-native-8.4")
        #expect(throws: Self.mismatch) { try verifier.verifyPHP(fpm) }
    }

    @Test func legacyBundledPHPAcceptsOnlyTheCLIName() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.url)
        let build = layout.runtimes.developmentRuntimesDirectory.appendingPathComponent("php-php-8.5.11-arm64")
        var hashes: [String: String] = [:]
        for name in ["php-native-8.5", "php-native-fpm-8.5", "BUILD-INFO.txt"] {
            let file = try folder.write(name, to: "runtimes/php-php-8.5.11-arm64/\(name)")
            hashes[name] = try FileDigest.hexSHA256(of: file)
        }
        let receipt: [String: Any] = ["schemaVersion": 1, "archiveSHA256": digest("a"), "fileSHA256": hashes]
        try AtomicFile.write(
            try JSONSerialization.data(withJSONObject: receipt), to: build.appendingPathComponent("jerd-receipt.json"))
        let verifier = ManagedExecutableVerifier(layout: layout)
        #expect(try verifier.verifyPHP(build.appendingPathComponent("php-native-8.5")).relativePath == "php-native-8.5")
        for name in ["php-native-fpm-8.5", "BUILD-INFO.txt"] {
            #expect(throws: Self.mismatch) {
                try verifier.verifyPHP(build.appendingPathComponent(name))
            }
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
