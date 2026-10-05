import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@Suite struct CLICompanionStoreTests {
    private let bundled = CLICompanions(
        composerPath: "/data/runtimes/composer/composer.phar", laravelPath: "/data/runtimes/laravel/bin/laravel",
        composerVersion: "2.10.3", laravelVersion: "5.32.0")

    @Test func goldenRecordFromAnInstalledCopyDecodesAndEncodesInTheSameForm() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let golden = try Fixture.data("Installed/cli-tools.json")
        try AtomicFile.write(golden, to: folder.path("cli-tools.json"))
        let store = CLICompanionStore(file: folder.path("cli-tools.json"))
        let record = try #require(try store.load())
        #expect(record.composerVersion == "2.10.3" && record.laravelVersion == "5.32.0")
        // The default encoder writes keys in hash order, as the old writer did; the form is what must match.
        let encoded = try JSONFileFormat.compact.makeEncoder().encode(record)
        #expect(encoded.count == golden.count)
        #expect(String(decoding: encoded, as: UTF8.self).contains(#""composerPath":"\/Users\/example\/"#))
        #expect(try JSONDecoder().decode(CLICompanions.self, from: encoded) == record)
    }

    @Test func bundledToolsBecomeTheFirstSelection() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = CLICompanionStore(file: folder.path("cli-tools.json"))
        #expect(try store.load() == nil)
        #expect(try store.recordBundled(bundled) == bundled)
        #expect(try store.load() == bundled)
        #expect(permissions(folder.path("cli-tools.json")) == 0o600)
    }

    @Test func laterSelectionsSurviveTheBootstrapAndMissingVersionsAreFilled() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = CLICompanionStore(file: folder.path("cli-tools.json"))
        let older = CLICompanions(composerPath: bundled.composerPath, laravelPath: "/updates/laravel")
        try AtomicFile.write(try JSONEncoder().encode(older), to: folder.path("cli-tools.json"))
        let merged = try store.recordBundled(bundled)
        #expect(merged.composerPath == bundled.composerPath && merged.composerVersion == "2.10.3")
        #expect(merged.laravelPath == "/updates/laravel" && merged.laravelVersion == nil)
    }

    @Test func corruptRecordIsNeverReset() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let broken = Data("broken tools record".utf8)
        try AtomicFile.write(broken, to: folder.path("cli-tools.json"))
        let store = CLICompanionStore(file: folder.path("cli-tools.json"))
        #expect(throws: JerdError.self) { try store.load() }
        #expect(throws: JerdError.self) { try store.recordBundled(bundled) }
        #expect(try Data(contentsOf: folder.path("cli-tools.json")) == broken)
    }

    @Test func activationReplacesOnlyItsOwnTool() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = CLICompanionStore(file: folder.path("cli-tools.json"))
        try store.recordBundled(bundled)
        let composer = try managed(.composer, executable: "composer.phar", folder: folder)
        let next = try store.activate(composer)
        #expect(next.composerPath == composer.executable.path && next.composerVersion == "2.11.0")
        #expect(next.laravelPath == bundled.laravelPath && next.laravelVersion == "5.32.0")
        #expect(throws: JerdError.invalid("This runtime is not a CLI companion.")) {
            try store.activate(try managed(.php, executable: "php", folder: folder))
        }
    }

    @Test func activationNeedsARecord() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let store = CLICompanionStore(file: folder.path("cli-tools.json"))
        #expect(throws: JerdError.self) { try store.activate(try managed(.composer, executable: "c", folder: folder)) }
    }

    private func managed(_ kind: RuntimeKind, executable: String, folder: TemporaryFolder) throws -> ManagedRuntime {
        let receipt = BuildReceipt(
            kind: kind, version: "2.11.0", releaseVersion: "2.11.0", archiveSHA256: digest("a"),
            executable: try #require(RelativePath(executable)), secondaryExecutable: nil,
            files: [try #require(RelativePath(executable)): digest("b")])
        return ManagedRuntime(receipt: receipt, directory: folder.path("runtime-updates/\(kind.rawValue)-2.11.0-arm64"))
    }
}
