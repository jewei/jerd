import Darwin
import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

/// RT-6: payload folders that an older Jerd installed are verified with their own receipt form before use.
@Suite struct LegacyPayloadVerifierTests {
    /// The golden folders: the exact receipt forms of the old tools (indent 2, sorted keys, extra keys).
    private static let golden: [(PayloadGroup, String, [String])] = [
        (.development, "caddy-v2.11.4-arm64", ["LICENSE", "README.md", "caddy"]),
        (.database, "redis-8.8.3-arm64", ["LICENSE", "bin/redis-cli", "bin/redis-server"]),
        (.mail, "mailpit-1.31.3-arm64", ["LICENSE", "README.md", "mailpit"]),
        (.storage, "rustfs-1.0.0-arm64", ["LICENSE", "rustfs"]),
    ]
    private static let executables: Set<String> = ["caddy", "redis-cli", "redis-server", "mailpit", "rustfs"]

    /// Copies a golden folder into a fresh data root with the modes that the old installers set.
    private func install(_ group: PayloadGroup, _ id: String, in folder: TemporaryFolder) throws -> (DataLayout, URL) {
        let layout = DataLayout(root: folder.path("data"))
        let directory = layout.runtimes.payloadDirectory(for: group)
        try OwnedDirectory.create(directory)
        let source = try #require(Bundle.module.url(forResource: "Fixtures/Legacy", withExtension: nil))
            .appendingPathComponent(directory.lastPathComponent).appendingPathComponent(id)
        let target = directory.appendingPathComponent(id)
        try FileManager.default.copyItem(at: source, to: target)
        let names = try #require(FileManager.default.subpaths(atPath: target.path))
        for name in names {
            let url = target.appendingPathComponent(name)
            let isFolder = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
            let isExecutable = Self.executables.contains(url.lastPathComponent)
            chmod(url.path, isFolder || isExecutable ? 0o700 : 0o600)
        }
        chmod(target.path, 0o700)
        return (layout, target)
    }

    @Test(arguments: golden.indices)
    func goldenLegacyFolderOfEachGroupVerifies(_ index: Int) async throws {
        let (group, id, files) = Self.golden[index]
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let (layout, target) = try install(group, id, in: folder)
        try folder.write("finder", to: "data/\(target.deletingLastPathComponent().lastPathComponent)/\(id)/.DS_Store")
        let payload = try await LegacyPayloadVerifier(layout: layout).verify(id: id, group: group)
        #expect(payload.id == id && payload.group == group && payload.directory.path == target.path)
        #expect(payload.receipt.format == LegacyPayloadReceipt.Format(group: group))
        #expect(payload.receipt.fileHashes.keys.map(\.string).sorted() == files)
    }

    /// Changes one golden folder with `change`, then requires the "changed" error for `path`.
    private func expectChange(
        _ index: Int, path: String, _ change: (URL) throws -> Void, afterwards: (URL) throws -> Void = { _ in }
    ) async throws {
        let (group, id, _) = Self.golden[index]
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let (layout, target) = try install(group, id, in: folder)
        try change(target)
        await #expect(throws: Self.changed(path)) {
            try await LegacyPayloadVerifier(layout: layout).verify(id: id, group: group)
        }
        try afterwards(target)
    }

    @Test(arguments: golden.indices)
    func changedExtraOrMissingFilesFailAndArePreserved(_ index: Int) async throws {
        let first = Self.golden[index].2[0]
        try await expectChange(index, path: first) { target in
            try AtomicFile.write(Data("preserve this".utf8), to: target.appendingPathComponent(first))
        } afterwards: { target in
            let kept = try Data(contentsOf: target.appendingPathComponent(first))
            #expect(kept == Data("preserve this".utf8))
        }
        try await expectChange(index, path: "injected.dylib") { target in
            try Data("dylib".utf8).write(to: target.appendingPathComponent("injected.dylib"))
        }
        try await expectChange(index, path: "LICENSE") { target in
            try FileManager.default.removeItem(at: target.appendingPathComponent("LICENSE"))
        }
    }

    @Test func databaseExecutableWithoutItsExecuteBitFails() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let (layout, target) = try install(.database, "redis-8.8.3-arm64", in: folder)
        chmod(target.appendingPathComponent("bin/redis-server").path, 0o600)
        await #expect(throws: JerdError.invalid("The installed runtime is not executable: bin/redis-server.")) {
            try await LegacyPayloadVerifier(layout: layout).verify(id: "redis-8.8.3-arm64", group: .database)
        }
    }

    @Test func corruptReceiptFailsAndIsPreserved() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let (layout, target) = try install(.mail, "mailpit-1.31.3-arm64", in: folder)
        let receipt = target.appendingPathComponent("receipt.json")
        try AtomicFile.write(Data("{broken".utf8), to: receipt)
        await #expect(
            throws: JerdError.invalid("The installed runtime receipt is invalid. Existing files were preserved.")
        ) {
            try await LegacyPayloadVerifier(layout: layout).verify(id: "mailpit-1.31.3-arm64", group: .mail)
        }
        #expect(try Data(contentsOf: receipt) == Data("{broken".utf8))
    }

    @Test(arguments: ["../escape", ".install-ABC", "", "a/b"])
    func unsafeIdentifierIsRefusedBeforeAnyFileAccess(_ id: String) async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.path("data"))
        await #expect(throws: JerdError.invalid("The runtime ID \(id) is invalid.")) {
            try await LegacyPayloadVerifier(layout: layout).verify(id: id, group: .mail)
        }
        #expect(FileProbe.presence(at: folder.path("data")) == .absent)
    }

    @Test func linkedFolderIsRefused() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let (layout, target) = try install(.mail, "mailpit-1.31.3-arm64", in: folder)
        let link = target.deletingLastPathComponent().appendingPathComponent("mailpit-1.31.4-arm64")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        await #expect(throws: JerdError.invalid("The runtime directory is invalid.")) {
            try await LegacyPayloadVerifier(layout: layout).verify(id: "mailpit-1.31.4-arm64", group: .mail)
        }
    }

    @Test func currentPayloadFolderIsNotALegacyFolder() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let (layout, target) = try install(.mail, "mailpit-1.31.3-arm64", in: folder)
        try FileManager.default.removeItem(at: target.appendingPathComponent("receipt.json"))
        await #expect(throws: JerdError.self) {
            try await LegacyPayloadVerifier(layout: layout).verify(id: "mailpit-1.31.3-arm64", group: .mail)
        }
    }

    private static func changed(_ path: String) -> JerdError {
        .invalid("The installed runtime changed: \(path). Existing files were preserved.")
    }
}
