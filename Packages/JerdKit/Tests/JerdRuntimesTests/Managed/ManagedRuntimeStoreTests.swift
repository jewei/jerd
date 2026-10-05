import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@Suite struct ManagedRuntimeStoreTests {
    private func release(_ hash: String?, kind: RuntimeKind = .php) throws -> RuntimeRelease {
        RuntimeRelease(
            kind: kind, version: "8.5.11",
            artifact: .archive(try .runtime("https://github.com/a/b.tar.gz"), size: .exact(10)),
            archiveSHA256: hash, signatureURL: hash == nil ? try .runtime("https://github.com/a/b.asc") : nil,
            releasePage: try .runtime("https://github.com/a"), architecture: .arm64)
    }

    /// Writes a build folder with one file and a valid receipt, as an installed copy has.
    @discardableResult
    private func build(
        _ folder: TemporaryFolder, name: String, kind: RuntimeKind = .php, hash: String, content: String = "php"
    ) throws -> URL {
        let file = try folder.write(content, to: "\(name)/php", mode: 0o700)
        let receipt = BuildReceipt(
            kind: kind, version: "8.5.11", releaseVersion: "8.5.11", archiveSHA256: hash,
            executable: try #require(RelativePath("php")), secondaryExecutable: nil,
            files: [try #require(RelativePath("php")): try FileDigest.hexSHA256(of: file)])
        try AtomicFile.write(try receipt.encoded(), to: folder.path("\(name)/update-receipt.json"))
        return folder.path(name)
    }

    @Test func legacyFolderIsReusedOnlyForTheSameDigest() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = ManagedRuntimeStore(directory: folder.url, architecture: .arm64)
        let legacy = try build(folder, name: "php-8.5.11-arm64", hash: digest("a"))
        #expect(try store.existing(release(digest("a")))?.directory == legacy)
        #expect(try store.existing(release(digest("b"))) == nil)
        let current = try build(folder, name: "php-8.5.11-arm64-\(digest("b"))", hash: digest("b"), content: "new")
        #expect(try store.existing(release(digest("b")))?.directory == current)
        #expect(Set(store.installed().map(\.id)).count == 2)
        #expect(try String(contentsOf: legacy.appendingPathComponent("php"), encoding: .utf8) == "php")
    }

    @Test func oneBadFolderDoesNotHideTheOthers() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try build(folder, name: "php-8.5.11-arm64", hash: digest("a"))
        try folder.write("{broken", to: "caddy-2.11.4-arm64/update-receipt.json")
        try build(folder, name: "php-8.5.11-x86_64", hash: digest("c"))
        try folder.write("no receipt", to: "notes/readme")
        let listing = ManagedRuntimeStore(directory: folder.url, architecture: .arm64).list()
        #expect(listing.compactMap(\.runtime).map(\.folderName) == ["php-8.5.11-arm64"])
        #expect(listing.count == 3)
        #expect(
            listing.contains(
                .unusable(
                    folder: "php-8.5.11-x86_64", reason: "The installed runtime directory does not match its receipt."))
        )
    }

    @Test func signedOrResolvedReleasesFindTheirBuildByVersion() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = ManagedRuntimeStore(directory: folder.url, architecture: .arm64)
        try build(folder, name: "mysql-8.5.11-arm64-\(digest("d"))", kind: .mysql, hash: digest("d"))
        let mysql = try release(nil, kind: .mysql)
        let found = try #require(try store.existing(mysql))
        #expect(found.matches(mysql))
        #expect(!found.matches(try release(digest("e"), kind: .mysql)))
    }

    @Test func conflictingReceiptInTheReleaseFolderIsAnError() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try build(folder, name: "caddy-8.5.11-arm64", kind: .php, hash: digest("a"))
        let caddy = try release(digest("a"), kind: .caddy)
        #expect(throws: JerdError.invalid("The installed runtime has conflicting metadata. It was preserved.")) {
            try ManagedRuntimeStore(directory: folder.url, architecture: .arm64).existing(caddy)
        }
    }

    @Test func verificationIgnoresFinderMetadataButNotOtherChanges() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = ManagedRuntimeStore(directory: folder.url, architecture: .arm64)
        let path = try build(folder, name: "php-8.5.11-arm64", hash: digest("a"))
        let receipt = try store.receipt(at: path)
        try folder.write("finder", to: "php-8.5.11-arm64/.DS_Store")
        try store.verify(receipt, at: path)
        try folder.write("extra", to: "php-8.5.11-arm64/extra")
        #expect(throws: JerdError.invalid("The installed runtime changed: extra. Existing files were preserved.")) {
            try store.verify(receipt, at: path)
        }
        try FileManager.default.removeItem(at: path.appendingPathComponent("extra"))
        try folder.write("changed", to: "php-8.5.11-arm64/php")
        #expect(throws: JerdError.invalid("The installed runtime changed: php. Existing files were preserved.")) {
            try store.verify(receipt, at: path)
        }
    }

    @Test func symbolicLinkInABuildIsRefused() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = ManagedRuntimeStore(directory: folder.url, architecture: .arm64)
        let path = try build(folder, name: "php-8.5.11-arm64", hash: digest("a"))
        try FileManager.default.createSymbolicLink(
            atPath: path.appendingPathComponent("link").path, withDestinationPath: "/etc")
        #expect(throws: JerdError.invalid("The prepared runtime contains a symbolic link.")) {
            try store.verify(try store.receipt(at: path), at: path)
        }
    }

    @Test func receiptOfALinkedFolderIsRefused() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let real = try build(folder, name: "real", hash: digest("a"))
        try FileManager.default.createSymbolicLink(at: folder.path("php-8.5.11-arm64"), withDestinationURL: real)
        #expect(throws: JerdError.invalid("The runtime directory is invalid.")) {
            try ManagedRuntimeStore(directory: folder.url).receipt(at: folder.path("php-8.5.11-arm64"))
        }
    }
}
