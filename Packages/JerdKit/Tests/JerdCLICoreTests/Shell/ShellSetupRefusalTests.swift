import Foundation
import JerdFoundation
import JerdTestSupport
import JerdWeb
import Testing

@testable import JerdCLICore

/// Every refusal happens before any write: the home folder stays byte for byte the same.
@Suite struct ShellSetupRefusalTests {
    private func expectRefusal(
        _ harness: ShellSetupHarness, signatures: FakeSignatureCheck = FakeSignatureCheck(),
        message: (String) -> Bool
    ) async {
        let before = harness.snapshot()
        await #expect {
            try await harness.installer(signatures: signatures).install()
        } throws: { error in
            message(FailureDetail.describe(error))
        }
        #expect(harness.snapshot() == before)
    }

    @Test func changedDefaultRuntimeCannotChangeShellFiles() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        try Data("changed PHP".utf8).write(to: URL(fileURLWithPath: harness.php.cliPath))
        await expectRefusal(harness) { $0 == "PHP 8.5: The installed PHP executable failed verification." }
    }

    @Test func changedPinnedManagedRuntimeIsRefused() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let other = try harness.fixture.installPHP("8.3")
        try Data("changed PHP".utf8).write(to: URL(fileURLWithPath: other.cliPath))
        let site = try harness.fixture.site("app", project: "code/app", selection: .pinned(other.id))
        try harness.fixture.saveDefault(harness.php, sites: [site], others: [other])
        await expectRefusal(harness) { $0 == "PHP 8.3: The installed PHP executable failed verification." }
    }

    @Test func managedRuntimeWithoutAReceiptIsRefused() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let loose = try harness.fixture.directory.file(
            "home/Library/Application Support/Jerd/runtimes/php-loose/php", "loose", mode: 0o700)
        let other = harness.fixture.runtime("8.3", cliPath: loose.path)
        try harness.fixture.saveDefault(other)
        await expectRefusal(harness) { $0.hasPrefix("PHP 8.3: ") }
    }

    @Test func unusedUnmanagedRuntimeDoesNotBlockTheSetup() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let other = harness.fixture.runtime("8.3", cliPath: "/elsewhere/php")
        try harness.fixture.saveDefault(harness.php, others: [other])
        _ = try await harness.installer().install()
    }

    @Test func missingDefaultIsRefused() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        try harness.fixture.save(AppConfiguration(runtimes: [harness.php]))
        await expectRefusal(harness) { $0 == "Select a default PHP runtime in Jerd." }
    }

    @Test func missingCompanionsAreRefused() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        try FileManager.default.removeItem(at: harness.layout.runtimes.cliToolsFile)
        await expectRefusal(harness) { $0 == "Open Jerd to install Composer and the Laravel installer first." }
    }

    @Test func missingCompanionScriptIsRefused() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let companions = try harness.fixture.installCompanions()
        try FileManager.default.removeItem(atPath: companions.laravelPath)
        await expectRefusal(harness) { $0 == "Open Jerd to install Composer and the Laravel installer first." }
    }

    @Test func missingLauncherIsRefused() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        try FileManager.default.removeItem(at: harness.launcher)
        await expectRefusal(harness) { $0 == "Build or install a Jerd app with its command launcher first." }
    }

    @Test func invalidLauncherSignatureIsRefused() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let refusal = JerdError.invalid("The Jerd command launcher has no valid code signature.")
        await expectRefusal(harness, signatures: FakeSignatureCheck(refusal: refusal)) { $0 == refusal.message }
    }

    @Test func symbolicLinkedZshrcIsPreserved() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let target = try harness.fixture.directory.file("home/dotfiles/zshrc", ShellSetupHarness.original)
        try FileManager.default.removeItem(at: harness.zshrc)
        try FileManager.default.createSymbolicLink(at: harness.zshrc, withDestinationURL: target)
        await expectRefusal(harness) { $0.hasPrefix("\(harness.zshrc.path) is a symbolic link.") }
        #expect(contents(target) == ShellSetupHarness.original)
    }

    @Test func hardLinkedZshrcIsPreserved() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        try FileManager.default.linkItem(at: harness.zshrc, to: harness.home.appendingPathComponent("zshrc-copy"))
        await expectRefusal(harness) { $0.contains("has more than one link") }
    }

    @Test func nonUTF8ZshrcIsPreserved() async throws {
        let harness = try ShellSetupHarness(zshrc: Data([0x65, 0x63, 0xFF, 0xFE, 0x0A]))
        defer { harness.remove() }
        await expectRefusal(harness) { $0.hasPrefix("\(harness.zshrc.path) is not UTF-8 text.") }
    }

    @Test(arguments: [
        "# >>> Jerd PHP CLI >>>\n",
        "# <<< Jerd PHP CLI <<<\n# >>> Jerd PHP CLI >>>\n",
        ShellPathBlockEditor.block + ShellPathBlockEditor.block,
    ])
    func malformedBlockNeedsManualReview(zshrc: String) async throws {
        let harness = try ShellSetupHarness(zshrc: Data(zshrc.utf8))
        defer { harness.remove() }
        await expectRefusal(harness) {
            $0.hasPrefix("The Jerd PATH block in \(harness.zshrc.path) needs manual review.")
        }
    }

    @Test(arguments: ["php", "composer", "laravel"])
    func unrelatedCommandIsNotChanged(name: String) async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        try harness.fixture.directory.file("home/Library/Application Support/Jerd/bin/\(name)", "#!/bin/sh\n")
        await expectRefusal(harness) { $0.hasPrefix("An unrelated \(name) command already exists") }
    }

    @Test func linkToAnotherProgramIsNotChanged() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        try OwnedDirectory.create(harness.bin)
        try FileManager.default.createSymbolicLink(
            atPath: harness.bin.appendingPathComponent("php").path, withDestinationPath: "/opt/homebrew/bin/php")
        await expectRefusal(harness) { $0.hasPrefix("An unrelated php command already exists") }
    }

    @Test func linkedBinFolderIsRefused() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let elsewhere = try harness.fixture.directory.folder("home/elsewhere")
        try FileManager.default.createSymbolicLink(at: harness.bin, withDestinationURL: elsewhere)
        await expectRefusal(harness) { $0.hasPrefix("The command folder") }
    }

    @Test func folderAtAStageNameIsPreserved() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        try harness.fixture.directory.folder("home/.zshrc.jerd-tmp")
        await expectRefusal(harness) { $0.contains("is in the way of the setup") }
    }
}
