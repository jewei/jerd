import Foundation
import JerdFoundation
import JerdWeb
import Testing

@testable import JerdCLICore

@Suite struct ShellSetupInstallerTests {
    @Test func setupInstallsLauncherLinksBlockAndBackup() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let report = try await harness.installer().install()
        let expected = ShellSetupHarness.original + Data("\n".utf8) + Data(ShellPathBlockEditor.block.utf8)
        #expect(contents(harness.zshrc) == expected)
        #expect(mode(harness.zshrc) == 0o644)
        #expect(isAbsent(harness.zprofile))
        #expect(report.changedFiles == [harness.zshrc])
        #expect(report.unchangedFiles.isEmpty)
        let backup = try #require(report.backupDirectory)
        #expect(backup == harness.layout.shellBackupsDirectory.appendingPathComponent("20260304-050607-000000"))
        #expect(contents(backup.appendingPathComponent(".zshrc")) == ShellSetupHarness.original)
        #expect(mode(backup.appendingPathComponent(".zshrc")) == 0o600)
        #expect(mode(backup) == 0o700)
        #expect(mode(harness.layout.shellBackupsDirectory) == 0o700)
        let launcher = harness.bin.appendingPathComponent("JerdCLI")
        #expect(contents(launcher) == ShellSetupHarness.launcherBytes)
        #expect(mode(launcher) == 0o700)
        #expect(mode(harness.bin) == 0o700)
        for command in CLICommand.allCases {
            let link = harness.bin.appendingPathComponent(command.rawValue)
            #expect(linkText(link) == "JerdCLI")
            #expect(link.resolvingSymlinksInPath() == launcher.resolvingSymlinksInPath())
        }
        #expect(
            report.summary == [
                "php, composer, and laravel now select the registered site's PHP, or the Jerd default outside a site.",
                "Shell backups: \(backup.path)",
                "Run exec zsh -l in an existing terminal to load the PATH change.",
            ])
    }

    @Test func secondSetupKeepsOneBlockAndChangesNoShellFile() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        _ = try await harness.installer().install()
        let first = contents(harness.zshrc)
        let firstInode = inode(harness.zshrc)
        let report = try await harness.installer(at: Date(timeIntervalSince1970: 1_772_600_800)).install()
        #expect(contents(harness.zshrc) == first)
        #expect(inode(harness.zshrc) == firstInode)
        #expect(report.changedFiles.isEmpty)
        #expect(report.unchangedFiles == [harness.zshrc])
        #expect(report.backupDirectory == nil)
        #expect(text(harness.zshrc).components(separatedBy: ShellPathBlockEditor.startMarker).count == 2)
        #expect(report.summary.last == "The shell files already contain the Jerd PATH block.")
        let backups = try FileManager.default.contentsOfDirectory(atPath: harness.layout.shellBackupsDirectory.path)
        #expect(backups.count == 1)
    }

    @Test func bothExistingStartupFilesGetTheBlockAndKeepTheirModes() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        try harness.fixture.directory.file("home/.zprofile", "eval \"$(brew shellenv)\"", mode: 0o600)
        let report = try await harness.installer().install()
        #expect(report.changedFiles == [harness.zprofile, harness.zshrc])
        #expect(text(harness.zprofile) == "eval \"$(brew shellenv)\"\n\n" + ShellPathBlockEditor.block)
        #expect(mode(harness.zprofile) == 0o600)
        #expect(mode(harness.zshrc) == 0o644)
        let backup = try #require(report.backupDirectory)
        #expect(text(backup.appendingPathComponent(".zprofile")) == "eval \"$(brew shellenv)\"")
    }

    @Test func withoutStartupFilesOnlyAPrivateZshrcIsCreatedAndNothingIsBackedUp() async throws {
        let harness = try ShellSetupHarness(zshrc: nil)
        defer { harness.remove() }
        let report = try await harness.installer().install()
        #expect(text(harness.zshrc) == ShellPathBlockEditor.block)
        #expect(mode(harness.zshrc) == 0o600)
        #expect(isAbsent(harness.zprofile))
        #expect(report.backupDirectory == nil)
        #expect(isAbsent(harness.layout.shellBackupsDirectory))
    }

    @Test func oldBlockIsReplacedInPlace() async throws {
        let old = "a\n# >>> Jerd PHP CLI >>>\nexport PATH=/old:$PATH\n# <<< Jerd PHP CLI <<<\nb\n"
        let harness = try ShellSetupHarness(zshrc: Data(old.utf8))
        defer { harness.remove() }
        _ = try await harness.installer().install()
        #expect(text(harness.zshrc) == "a\n" + ShellPathBlockEditor.block + "b\n")
    }

    @Test func legacyDirectPHPLinkAndOwnLinksAreReplaced() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        try OwnedDirectory.create(harness.bin)
        try FileManager.default.createSymbolicLink(
            at: harness.bin.appendingPathComponent("php"), withDestinationURL: URL(fileURLWithPath: harness.php.cliPath)
        )
        try FileManager.default.createSymbolicLink(
            atPath: harness.bin.appendingPathComponent("composer").path, withDestinationPath: "JerdCLI")
        _ = try await harness.installer().install()
        #expect(linkText(harness.bin.appendingPathComponent("php")) == "JerdCLI")
        #expect(linkText(harness.bin.appendingPathComponent("composer")) == "JerdCLI")
    }

    @Test func crashLeftoversAreRemovedBeforeStaging() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        try OwnedDirectory.create(harness.bin)
        try harness.fixture.directory.file("home/.zshrc.jerd-tmp", "partial")
        try harness.fixture.directory.file("home/Library/Application Support/Jerd/bin/.JerdCLI-next", "partial")
        try FileManager.default.createSymbolicLink(
            atPath: harness.bin.appendingPathComponent(".php-next").path, withDestinationPath: "JerdCLI")
        _ = try await harness.installer().install()
        #expect(isAbsent(harness.home.appendingPathComponent(".zshrc.jerd-tmp")))
        #expect(isAbsent(harness.bin.appendingPathComponent(".JerdCLI-next")))
        #expect(isAbsent(harness.bin.appendingPathComponent(".php-next")))
        #expect(contents(harness.bin.appendingPathComponent("JerdCLI")) == ShellSetupHarness.launcherBytes)
    }

    @Test func managedBuildReceiptIsAccepted() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let build = harness.layout.runtimes.managedRuntimesDirectory.appendingPathComponent("php-8.4.1-arm64-build")
        try OwnedDirectory.create(build)
        let php = build.appendingPathComponent("php-native-8.4")
        try Data(CLIFixture.fakePHP.utf8).write(to: php)
        let hash = try FileDigest.hexSHA256(of: php)
        let receipt = """
            {"schemaVersion":1,"kind":"php","version":"8.4.1","releaseVersion":"8.4.1",\
            "archiveSHA256":"\(String(repeating: "b", count: 64))","executable":"php-native-8.4",\
            "files":{"php-native-8.4":"\(hash)"}}
            """
        try AtomicFile.write(Data(receipt.utf8), to: build.appendingPathComponent("update-receipt.json"))
        try harness.fixture.saveDefault(harness.fixture.runtime("8.4", cliPath: php.path))
        _ = try await harness.installer().install()
        #expect(linkText(harness.bin.appendingPathComponent("php")) == "JerdCLI")
    }

    /// Review cli-r1 M2: an imported PHP that a site pins is the user's choice and never blocks the setup.
    @Test func importedPinnedRuntimeIsTrusted() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let local = try harness.fixture.directory.file("opt/php-custom/bin/php", "custom build", mode: 0o755)
        let imported = harness.fixture.runtime("8.4.custom", cliPath: local.path)
        let site = try harness.fixture.site("other", project: "code/other", selection: .pinned(imported.id))
        try harness.fixture.saveDefault(harness.php, sites: [site], others: [imported])
        _ = try await harness.installer().install()
        #expect(linkText(harness.bin.appendingPathComponent("php")) == "JerdCLI")
    }

    @Test func importedDefaultRuntimeIsTrusted() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let local = try harness.fixture.directory.file("opt/php/bin/php", "custom build", mode: 0o755)
        try harness.fixture.saveDefault(harness.fixture.runtime("8.4.custom", cliPath: local.path))
        _ = try await harness.installer().install()
        #expect(contents(harness.bin.appendingPathComponent("JerdCLI")) == ShellSetupHarness.launcherBytes)
    }
}
