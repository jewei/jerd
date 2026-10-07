import Foundation
import JerdFoundation
import JerdManifest
import JerdProcess
import JerdRuntimes
import Testing

@Suite struct PinnedPayloadPreparerTests {
    private let platform = HostPlatform(architecture: .arm64, osMajor: 15)

    /// A repository folder with a catalog of one Mailpit pin and its archive served by a fake fetcher.
    private func mailpitRepository(_ folder: TemporaryFolder) throws -> (FakeFetcher, RuntimePin) {
        var tar = TarBuilder()
        tar.file("mailpit", "binary", mode: "0000755")
        tar.file("LICENSE", "MIT")
        tar.file("README.md", "readme")
        tar.file("extra.txt", "not selected")
        let url = try URL.runtime(
            "https://github.com/axllent/mailpit/releases/download/v1.31.3/mailpit-darwin-arm64.tar.gz")
        let archive = PinnedArchive(url: url, size: Int64(tar.data.count), sha256: FileDigest.hexSHA256(of: tar.data))
        let pin = RuntimePin(
            id: "mailpit-1.31.3-arm64", kind: .mailpit, version: "1.31.3", archive: archive,
            releasePage: try .runtime("https://github.com/axllent/mailpit/releases/tag/v1.31.3"))
        try OwnedDirectory.create(folder.path("Runtimes"))
        try JSONEncoder().encode(RuntimePinCatalog(architecture: .arm64, pins: [pin]))
            .write(to: folder.path("Runtimes/runtimes.json"))
        return (FakeFetcher([url: tar.data]), pin)
    }

    @Test func pinPreparesIntoTheBundleLayoutAndTheAppInstallsIt() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let (fetcher, pin) = try mailpitRepository(folder)
        let commands = ScriptedCommandRunner { _ in CommandResult(status: 0, output: "mailpit v1.31.3 darwin/arm64") }
        let preparer = PinnedPayloadPreparer(
            catalogDirectory: folder.path("Runtimes"), output: folder.path("payloads"), fetcher: fetcher,
            commands: commands, platform: platform, minimumMacOS: .jerdKitMinimum)
        let catalog = try preparer.catalog()
        let receipt = try await preparer.prepare(pin, architecture: catalog.architecture, tools: PreparationTools())
        try preparer.writeCatalog()
        #expect(receipt.id == pin.id && receipt.archiveSHA256 == pin.archive?.sha256)
        #expect(Set(receipt.files.keys) == ["mailpit", "LICENSE", "README.md"])
        #expect(try preparer.folder(for: pin).path.hasSuffix("payloads/mail/mailpit-1.31.3-arm64"))
        let bootstrap = BundledRuntimeBootstrap(
            resources: folder.path("payloads"), layout: DataLayout(root: folder.path("data")), architecture: .arm64)
        let installed = try await bootstrap.installMail()
        #expect(installed.id == receipt.folderID && installed.version == "1.31.3")
    }

    @Test func earlierPreparationIsVerifiedAndKept() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let (fetcher, pin) = try mailpitRepository(folder)
        let commands = ScriptedCommandRunner { _ in CommandResult(status: 0, output: "mailpit v1.31.3") }
        let preparer = PinnedPayloadPreparer(
            catalogDirectory: folder.path("Runtimes"), output: folder.path("payloads"), fetcher: fetcher,
            commands: commands, platform: platform, minimumMacOS: .jerdKitMinimum)
        let first = try await preparer.prepare(pin, architecture: .arm64, tools: PreparationTools())
        let downloads = fetcher.requests.count
        #expect(try await preparer.prepare(pin, architecture: .arm64, tools: PreparationTools()) == first)
        #expect(fetcher.requests.count == downloads)
        try folder.write("changed", to: "payloads/mail/mailpit-1.31.3-arm64/LICENSE")
        await #expect(throws: JerdError.self) {
            try await preparer.prepare(pin, architecture: .arm64, tools: PreparationTools())
        }
    }

    /// An interrupted `./dev runtimes prepare` leaves staging folders in the group folders of the output.
    @Test func abandonedStagingFoldersOfTheOutputAreRemoved() throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        for group in PayloadGroup.allCases {
            try folder.write("partial", to: "payloads/\(group.rawValue)/.install-CRASH/download")
        }
        try folder.write("keep", to: "payloads/mail/mailpit-1.31.3-arm64/mailpit")
        let inUse = try StagingFolder(in: folder.path("payloads/database"))
        let preparer = PinnedPayloadPreparer(
            catalogDirectory: folder.path("Runtimes"), output: folder.path("payloads"), fetcher: FakeFetcher(),
            commands: ScriptedCommandRunner(), platform: platform, minimumMacOS: .jerdKitMinimum)
        #expect(preparer.removeAbandonedStaging() == PayloadGroup.allCases.map { "\($0.rawValue)/.install-CRASH" })
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: folder.path("payloads/mail").path) == [
                "mailpit-1.31.3-arm64"
            ])
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: folder.path("payloads/database").path) == [
                inUse.url.lastPathComponent
            ])
        inUse.remove()
    }

    @Test func lockedLaravelProjectInstallsExactlyItsPinnedLock() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try folder.write("{}", to: "Runtimes/laravel-installer/composer.json")
        let lock = try folder.write("{\"packages\":[]}", to: "Runtimes/laravel-installer/composer.lock")
        let pin = RuntimePin(
            id: "laravel-installer-5.32.0", kind: .laravel, version: "5.32.0", archive: nil,
            composerProject: PinnedComposerProject(
                directory: try #require(RelativePath("laravel-installer")),
                lockSHA256: try FileDigest.hexSHA256(of: lock)),
            releasePage: try .runtime("https://github.com/laravel/installer/releases/tag/v5.32.0"))
        let commands = ScriptedCommandRunner { request in
            if request.arguments.contains("install") {
                let script = request.workingDirectory.appendingPathComponent("vendor/laravel/installer/bin/laravel")
                try FileManager.default.createDirectory(
                    at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("<?php".utf8).write(to: script)
            }
            return CommandResult(status: 0, output: "Laravel Installer 5.32.0")
        }
        let preparer = PinnedPayloadPreparer(
            catalogDirectory: folder.path("Runtimes"), output: folder.path("payloads"), fetcher: FakeFetcher(),
            commands: commands, platform: platform, minimumMacOS: .jerdKitMinimum)
        let tools = PreparationTools(phpCLI: URL(fileURLWithPath: "/php"), composer: URL(fileURLWithPath: "/c.phar"))
        let receipt = try await preparer.prepare(pin, architecture: .arm64, tools: tools)
        #expect(receipt.archiveSHA256 == pin.composerProject?.lockSHA256)
        #expect(receipt.executable.string == "vendor/laravel/installer/bin/laravel")
        #expect(commands.requests.first?.arguments.prefix(3) == ["-n", "/c.phar", "install"])
    }

    @Test func committedCatalogMapsToReleasesThatThePolicyAccepts() throws {
        let preparer = PinnedPayloadPreparer(
            catalogDirectory: Fixture.repositoryFile("Runtimes"), output: URL(fileURLWithPath: "/nonexistent"),
            fetcher: FakeFetcher(), commands: ScriptedCommandRunner(), platform: platform, minimumMacOS: .jerdKitMinimum
        )
        let catalog = try preparer.catalog()
        let policy = ReleasePolicy(platform: platform)
        for pin in catalog.pins {
            let release = try preparer.release(for: pin, architecture: catalog.architecture)
            #expect(policy.check(release) == nil, "\(pin.id)")
        }
        let pin = try #require(catalog.pin(for: .mysql))
        let mysql = try preparer.release(for: pin, architecture: .arm64)
        #expect(mysql.archiveSHA256 != nil && mysql.signatureURL != nil)
        #expect(mysql.pinnedSignature == pin.signature && mysql.signatureURL == pin.signature?.url)
    }
}
