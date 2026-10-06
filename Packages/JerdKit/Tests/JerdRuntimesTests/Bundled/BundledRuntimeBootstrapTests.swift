import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@Suite struct BundledRuntimeBootstrapTests {
    private func mailBundle(_ folder: TemporaryFolder, name: String = "bundle", license: String = "MIT") throws -> URL {
        var builder = BundleBuilder(root: folder.path(name))
        try builder.add(
            .mailpit, id: "mailpit-1.31.3-arm64", version: "1.31.3",
            files: [
                .init(path: "mailpit", text: "binary", executable: true), .init(path: "LICENSE", text: license),
                .init(path: "README.md", text: "readme"),
            ])
        try builder.writeCatalog()
        return folder.path(name)
    }

    private func bootstrap(_ resources: URL, _ folder: TemporaryFolder) -> BundledRuntimeBootstrap {
        BundledRuntimeBootstrap(
            resources: resources, layout: DataLayout(root: folder.path("data")), architecture: .arm64)
    }

    @Test func mailpitInstallsIntoAPrivateContentAddressedFolder() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let installed = try await bootstrap(try mailBundle(folder), folder).installMail()
        #expect(installed.id.hasPrefix("mailpit-1.31.3-arm64-") && installed.version == "1.31.3")
        #expect(installed.directory.deletingLastPathComponent().lastPathComponent == "mail-runtimes")
        #expect(permissions(installed.directory) == 0o700)
        #expect(permissions(installed.executable) == 0o700)
        #expect(permissions(installed.directory.appendingPathComponent("LICENSE")) == 0o600)
        let names = try FileManager.default.contentsOfDirectory(atPath: installed.directory.path).sorted()
        #expect(names == ["LICENSE", "README.md", "mailpit", "payload-receipt.json"])
    }

    @Test func installedFolderIsReusedAndANewPayloadInstallsBesideIt() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let first = try await bootstrap(try mailBundle(folder), folder).installMail()
        let license = first.directory.appendingPathComponent("LICENSE")
        let before = try Data(contentsOf: license)
        #expect(try await bootstrap(try mailBundle(folder), folder).installMail() == first)
        let second = try await bootstrap(try mailBundle(folder, name: "signed", license: "MIT signed"), folder)
            .installMail()
        #expect(second.id != first.id)
        #expect(try Data(contentsOf: license) == before)
    }

    @Test func corruptInstalledFileFailsAndIsPreserved() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let bundle = try mailBundle(folder)
        let installed = try await bootstrap(bundle, folder).installMail()
        let license = installed.directory.appendingPathComponent("LICENSE")
        try AtomicFile.write(Data("preserve this corrupt file".utf8), to: license)
        await #expect(
            throws: JerdError.invalid("The installed runtime changed: LICENSE. Existing files were preserved.")
        ) {
            try await bootstrap(bundle, folder).installMail()
        }
        #expect(try Data(contentsOf: license) == Data("preserve this corrupt file".utf8))
    }

    /// RT-1: the first-launch verification and copy run on a GCD thread; a cancellation must stop them.
    @Test func cancellationStopsTheFirstLaunchInstallationWhileItRuns() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let bundle = try mailBundle(folder)
        try makeSparseFile(bundle.appendingPathComponent("mail/mailpit-1.31.3-arm64/mailpit"))
        let bootstrap = bootstrap(bundle, folder)
        let result = await cancelWhileRunning { try await bootstrap.installMail() }
        #expect(throws: CancellationError.self) { try result.get() }
        let mailRuntimes = folder.path("data/mail-runtimes")
        #expect(try FileManager.default.contentsOfDirectory(atPath: mailRuntimes.path).isEmpty)
    }

    @Test func bundleWithChangedOrExtraFilesIsRefusedBeforeAnyCopy() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let bundle = try mailBundle(folder)
        try folder.write("stale", to: "bundle/mail/mailpit-1.31.3-arm64/old-binary")
        await #expect(
            throws: JerdError.invalid("The bundled Mailpit runtime does not match its receipt. Install Jerd again.")
        ) {
            try await bootstrap(bundle, folder).installMail()
        }
        let mailRuntimes = folder.path("data/mail-runtimes")
        #expect(try FileManager.default.contentsOfDirectory(atPath: mailRuntimes.path).isEmpty)
    }

    @Test func receiptThatDoesNotMatchItsPinIsRefused() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var builder = BundleBuilder(root: folder.path("bundle"))
        try builder.add(
            .mailpit, id: "mailpit-1.31.3-arm64", version: "1.31.3",
            files: [.init(path: "mailpit", text: "b", executable: true)])
        let other = RuntimePinCatalog(
            architecture: .arm64,
            pins: builder.pins.map { pin in
                RuntimePin(
                    id: pin.id, kind: pin.kind, version: "1.31.4", archive: pin.archive, releasePage: pin.releasePage)
            })
        try JSONEncoder().encode(other).write(to: folder.path("bundle/runtimes.json"))
        await #expect(throws: JerdError.invalid("The bundled Mailpit receipt does not match its pin.")) {
            try await bootstrap(folder.path("bundle"), folder).installMail()
        }
    }

    @Test func bundleForAnotherArchitectureIsRefused() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let bootstrap = BundledRuntimeBootstrap(
            resources: try mailBundle(folder), layout: DataLayout(root: folder.path("data")), architecture: .intel)
        await #expect(throws: JerdError.unavailable("The bundled runtimes do not support this Mac.")) {
            try await bootstrap.installMail()
        }
    }

    @Test func databasesCanSkipInstalledEngines() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var builder = BundleBuilder(root: folder.path("bundle"))
        for (kind, id) in [(RuntimeKind.mysql, "mysql-8.4.11-arm64"), (.redis, "redis-8.8.3-arm64")] {
            try builder.add(
                kind, id: id, version: "8.8.3", files: [.init(path: "bin/server", text: id, executable: true)])
        }
        try builder.writeCatalog()
        let installed = try await bootstrap(folder.path("bundle"), folder).installDatabases(excluding: [.mysql])
        #expect(installed.map(\.kind) == [.redis])
        #expect(installed.first?.executable.lastPathComponent == "server")
    }

    @Test func developmentGroupReturnsPHPFromItsPinAndRecordsTheCLITools() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var builder = BundleBuilder(root: folder.path("bundle"))
        try builder.addDevelopment(phpVersion: "8.6.1")
        try builder.writeCatalog()
        let bootstrap = bootstrap(folder.path("bundle"), folder)
        #expect(try await bootstrap.needsDevelopmentRuntimes(hasPHP: true, hasCaddy: true))
        let runtimes = try await bootstrap.installDevelopment()
        #expect(runtimes.php.executable.lastPathComponent == "php-native-8.6")
        #expect(runtimes.php.secondaryExecutable?.lastPathComponent == "php-native-fpm-8.6")
        #expect(runtimes.companions.composerPath == runtimes.composer.executable.path)
        #expect(runtimes.companions.laravelPath.hasSuffix("vendor/laravel/installer/bin/laravel"))
        #expect(runtimes.companions.hasVersions)
        #expect(try await !bootstrap.needsDevelopmentRuntimes(hasPHP: true, hasCaddy: true))
        #expect(try await bootstrap.needsDevelopmentRuntimes(hasPHP: true, hasCaddy: false))
    }

    @Test func corruptToolRecordStopsTheBootstrapDecision() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let layout = DataLayout(root: folder.path("data"))
        try OwnedDirectory.create(layout.runtimes.developmentRuntimesDirectory)
        try AtomicFile.write(Data("broken".utf8), to: layout.runtimes.cliToolsFile)
        let bootstrap = BundledRuntimeBootstrap(resources: folder.path("none"), layout: layout, architecture: .arm64)
        await #expect(throws: JerdError.self) {
            try await bootstrap.needsDevelopmentRuntimes(hasPHP: true, hasCaddy: true)
        }
        #expect(try Data(contentsOf: layout.runtimes.cliToolsFile) == Data("broken".utf8))
    }

    @Test func bundledXZLibraryIsOfferedOnlyWhenTheStoragePayloadHasIt() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        var builder = BundleBuilder(root: folder.path("bundle"))
        try builder.add(
            .rustfs, id: "rustfs-1.0.0-arm64", version: "1.0.0",
            files: [
                .init(path: "rustfs", text: "b", executable: true), .init(path: "LICENSE", text: "a"),
                .init(path: "liblzma.5.dylib", text: "lzma"), .init(path: "XZ-LICENSE.txt", text: "0BSD"),
            ])
        try builder.writeCatalog()
        let library = try #require(try await bootstrap(folder.path("bundle"), folder).bundledLZMA())
        #expect(library.library.lastPathComponent == "liblzma.5.dylib")
        let storage = try await bootstrap(folder.path("bundle"), folder).installStorage()
        #expect(FileProbe.presence(at: storage.directory.appendingPathComponent("liblzma.5.dylib")) == .present)
    }
}
