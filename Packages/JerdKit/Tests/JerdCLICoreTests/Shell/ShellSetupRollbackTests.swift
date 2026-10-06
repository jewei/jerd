import Foundation
import JerdFoundation
import Testing

@testable import JerdCLICore

@Suite struct ShellSetupRollbackTests {
    @Test func concurrentEditStopsTheSetupAndRestoresTheEarlierFile() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let profile = Data("export A=1\n".utf8)
        try harness.fixture.directory.file("home/.zprofile", profile)
        let zshrc = harness.zshrc
        // The second signature check runs after the plan; the user edits .zshrc at that moment.
        let signatures = FakeSignatureCheck { call in
            if call == 2 { try? Data("edited by the user\n".utf8).write(to: zshrc) }
        }
        await #expect(
            throws: JerdError.unavailable("\(zshrc.path) changed during the setup. Set up the commands again.")
        ) {
            try await harness.installer(signatures: signatures).install()
        }
        #expect(contents(harness.zprofile) == profile)
        #expect(text(zshrc) == "edited by the user\n")
        #expect(isAbsent(harness.home.appendingPathComponent(".zprofile.jerd-tmp")))
        #expect(isAbsent(harness.home.appendingPathComponent(".zshrc.jerd-tmp")))
    }

    @Test func fileThatTheUserCreatesDuringSetupIsKept() async throws {
        let harness = try ShellSetupHarness(zshrc: nil)
        defer { harness.remove() }
        let zshrc = harness.zshrc
        let signatures = FakeSignatureCheck { call in
            if call == 2 { try? Data("new\n".utf8).write(to: zshrc) }
        }
        await #expect(throws: JerdError.self) { try await harness.installer(signatures: signatures).install() }
        #expect(text(zshrc) == "new\n")
    }

    @Test func rollbackRemovesAFileThatTheSetupCreated() async throws {
        let harness = try ShellSetupHarness(zshrc: nil)
        defer { harness.remove() }
        let created = try ShellFileChange(file: harness.zprofile, original: nil, mode: 0o600)
        try harness.fixture.directory.file("home/.zshrc", "now\n")
        let stale = try ShellFileChange(file: harness.zshrc, original: Data("before\n".utf8), mode: 0o644)
        await #expect(throws: JerdError.self) { try await harness.installer().replace([created, stale], backup: nil) }
        #expect(isAbsent(harness.zprofile))
        #expect(text(harness.zshrc) == "now\n")
    }

    /// Review cli-r1 L4: a new startup file is committed with `RENAME_EXCL`.
    @Test func newFileThatAppearsBeforeTheRenameIsNotOverwritten() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let stage = directory.url.appendingPathComponent(".zshrc.jerd-tmp")
        let target = try directory.file(".zshrc", "saved by an editor\n")
        try StagedFile.write(Data("block\n".utf8), to: stage, mode: 0o600)
        #expect(
            throws: JerdError.unavailable("\(target.path) appeared during the setup. Set up the commands again.")
        ) { try StagedFile.commitNew(stage, to: target) }
        #expect(text(target) == "saved by an editor\n")
        #expect(isAbsent(stage))
    }

    /// Review cli-r1 L4: the rollback restores only a file that still has the setup's bytes.
    @Test func rollbackKeepsAFileThatTheUserEditedAfterTheReplacement() async throws {
        let harness = try ShellSetupHarness(zshrc: nil)
        defer { harness.remove() }
        let profile = try ShellFileChange(file: harness.zprofile, original: Data("export A=1\n".utf8), mode: 0o600)
        let zshrc = try ShellFileChange(file: harness.zshrc, original: Data("export B=2\n".utf8), mode: 0o600)
        try harness.fixture.directory.file("home/.zprofile", "edited after the setup\n")
        try harness.fixture.directory.file("home/.zshrc", zshrc.updated)
        let backup = harness.layout.shellBackupsDirectory.appendingPathComponent("20260304-050607-000000")
        await #expect { try await harness.installer().restore([zshrc, profile], after: failure, backup: backup) }
            throws: { error in
                let message = (error as? JerdError)?.message ?? ""
                return (error as? JerdError)?.kind == .partialChange && message.contains(harness.zprofile.path)
                    && message.contains(backup.appendingPathComponent(".zprofile").path)
                    && !message.contains(harness.zshrc.path)
            }
        #expect(text(harness.zprofile) == "edited after the setup\n")
        #expect(text(harness.zshrc) == "export B=2\n")
    }

    @Test func failedLauncherCopyLeavesShellFilesAndNoStage() async throws {
        let harness = try ShellSetupHarness()
        defer { harness.remove() }
        let refusal = JerdError.invalid("copy is not signed")
        let failing = FakeSignatureCheckOnCopy(refusal: refusal)
        await #expect(throws: refusal) {
            try await ShellSetupInstaller(
                layout: harness.layout, home: harness.home, launcher: harness.launcher, signatures: failing
            ).install()
        }
        #expect(contents(harness.zshrc) == ShellSetupHarness.original)
        #expect(isAbsent(harness.bin.appendingPathComponent(".JerdCLI-next")))
        #expect(isAbsent(harness.bin.appendingPathComponent("JerdCLI")))
    }
}

private let failure = JerdError.unavailable("The disk is full.")

/// Accepts the launcher in the app and refuses the staged copy in `bin/`.
private struct FakeSignatureCheckOnCopy: LauncherSignatureChecking {
    let refusal: JerdError

    func checkSignature(of file: URL) throws {
        if file.lastPathComponent == ".JerdCLI-next" { throw refusal }
    }
}
