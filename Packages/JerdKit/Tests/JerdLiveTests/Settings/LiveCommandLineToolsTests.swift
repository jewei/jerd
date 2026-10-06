import JerdCLICore
import JerdUI
import Testing

@testable import JerdLive

@Suite("Live command-line tools")
struct LiveCommandLineToolsTests {
    @Test(arguments: [
        (CommandLineToolsState.notInstalled, CommandLineToolsStatus.notInstalled),
        (.installed, .installed), (.outdatedLauncher, .outdatedLauncher),
    ])
    func everyShellStateMapsToItsStatus(state: CommandLineToolsState, status: CommandLineToolsStatus) async {
        #expect(LiveCommandLineTools.status(state) == status)
        #expect(await LiveCommandLineTools(installer: FakeShellSetup(state)).status() == status)
    }

    @Test func installReturnsTheReportLines() async throws {
        let shell = FakeShellSetup(.notInstalled)

        let lines = try await LiveCommandLineTools(installer: shell).install()

        #expect(lines.first?.hasPrefix("php, composer, and laravel") == true)
        #expect(lines.contains("Run exec zsh -l in an existing terminal to load the PATH change."))
        #expect(await shell.installs == 1)
    }

    @Test func launchRefreshPassesThroughOnce() async throws {
        let shell = FakeShellSetup(.outdatedLauncher)

        #expect(try await LiveCommandLineTools(installer: shell).refreshLauncherIfInstalled())
        #expect(await shell.refreshes == 1)
        #expect(await shell.installs == 0)
    }
}
