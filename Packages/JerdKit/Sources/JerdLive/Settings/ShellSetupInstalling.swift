import JerdCLICore

/// The shell setup calls that the command-line tools port uses. `ShellSetupInstaller` is the
/// live type; tests use a fake, so no test changes a shell file or `bin/`.
package protocol ShellSetupInstalling: Sendable {
    func state() async -> CommandLineToolsState
    func install() async throws -> ShellSetupReport
    func refreshLauncherIfInstalled() async throws -> Bool
}

extension ShellSetupInstaller: ShellSetupInstalling {}
