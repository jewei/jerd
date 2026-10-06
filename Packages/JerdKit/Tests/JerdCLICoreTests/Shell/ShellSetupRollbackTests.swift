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

/// Accepts the launcher in the app and refuses the staged copy in `bin/`.
private struct FakeSignatureCheckOnCopy: LauncherSignatureChecking {
    let refusal: JerdError

    func checkSignature(of file: URL) throws {
        if file.lastPathComponent == ".JerdCLI-next" { throw refusal }
    }
}
