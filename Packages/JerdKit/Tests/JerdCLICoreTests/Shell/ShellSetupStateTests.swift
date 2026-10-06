import Foundation
import JerdFoundation
import Testing

@testable import JerdCLICore

/// The state that the app shows, and the launcher refresh at app launch.
@Suite struct ShellSetupStateTests {
    private static let newLauncher = Data("newer test launcher".utf8)

    @Test func freshHomeIsNotInstalled() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        #expect(await harness.installer().state() == .notInstalled)
    }

    @Test func completedSetupIsInstalled() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let installer = harness.installer()
        _ = try await installer.install()
        #expect(await installer.state() == .installed)
    }

    @Test func missingPathBlockOrLinkIsNotInstalled() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let installer = harness.installer()
        _ = try await installer.install()
        try FileManager.default.removeItem(at: harness.bin.appendingPathComponent("composer"))
        #expect(await installer.state() == .notInstalled)
        _ = try await installer.install()
        try ShellSetupHarness.original.write(to: harness.zshrc)
        #expect(await installer.state() == .notInstalled)
    }

    @Test func blockInALinkedStartupFileCounts() async throws {
        let harness = try ShellSetupHarness(zshrc: nil)
        defer { harness.remove() }
        let installer = harness.installer()
        _ = try await installer.install()
        let dotfiles = try harness.fixture.directory.file("dotfiles/zshrc", try #require(contents(harness.zshrc)))
        try FileManager.default.removeItem(at: harness.zshrc)
        try FileManager.default.createSymbolicLink(at: harness.zshrc, withDestinationURL: dotfiles)
        #expect(await installer.state() == .installed)
    }

    @Test func changedAppLauncherMakesTheCopyOutdated() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let installer = harness.installer()
        _ = try await installer.install()
        try Self.newLauncher.write(to: harness.launcher)
        #expect(await installer.state() == .outdatedLauncher)
    }

    @Test func refreshReplacesOnlyAnOutdatedLauncher() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let installer = harness.installer()
        _ = try await installer.install()
        let shellFile = contents(harness.zshrc)
        try Self.newLauncher.write(to: harness.launcher)
        #expect(try await installer.refreshLauncherIfInstalled())
        #expect(contents(harness.bin.appendingPathComponent("JerdCLI")) == Self.newLauncher)
        #expect(contents(harness.zshrc) == shellFile)
        #expect(await installer.state() == .installed)
        #expect(try await !installer.refreshLauncherIfInstalled())
    }

    @Test func refreshDoesNothingWhenTheCommandsAreNotInstalled() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let before = harness.snapshot()
        #expect(try await !harness.installer().refreshLauncherIfInstalled())
        #expect(isAbsent(harness.bin))
        #expect(harness.snapshot() == before)
    }

    @Test func refreshKeepsTheOldLauncherWhenTheNewSignatureIsRefused() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        _ = try await harness.installer().install()
        try Self.newLauncher.write(to: harness.launcher)
        let refusal = JerdError.invalid("not signed by this app's signer")
        await #expect(throws: refusal) {
            try await harness.installer(signatures: FakeSignatureCheck(refusal: refusal)).refreshLauncherIfInstalled()
        }
        #expect(contents(harness.bin.appendingPathComponent("JerdCLI")) == ShellSetupHarness.launcherBytes)
        #expect(isAbsent(harness.bin.appendingPathComponent(".JerdCLI-next")))
    }

    @Test func stateSummaryIsOneLine() {
        for state in [CommandLineToolsState.notInstalled, .installed, .outdatedLauncher] {
            #expect(!state.summary.isEmpty && !state.summary.contains("\n"))
        }
    }
}
