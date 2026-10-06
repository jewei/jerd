import JerdCLICore
import JerdUI

/// The `CommandLineToolsPort` of Advanced, implemented with the JerdCLICore shell setup.
package struct LiveCommandLineTools: CommandLineToolsPort {
    let installer: any ShellSetupInstalling

    package init(installer: any ShellSetupInstalling) {
        self.installer = installer
    }

    package init(installer: ShellSetupInstaller) {
        self.init(installer: installer as any ShellSetupInstalling)
    }

    package func status() async -> CommandLineToolsStatus {
        Self.status(await installer.state())
    }

    /// Installs the launcher and the PATH block, and returns the report lines.
    package func install() async throws -> [String] {
        try await installer.install().summary
    }

    /// Replaces an outdated `bin/JerdCLI` with this app's launcher. The app calls it once at
    /// launch, off the main actor. Shell files do not change.
    /// - Returns: true when the launcher was replaced.
    @discardableResult
    package func refreshLauncherIfInstalled() async throws -> Bool {
        try await installer.refreshLauncherIfInstalled()
    }

    /// The UI status of a shell setup state. The cases map one to one.
    package static func status(_ state: CommandLineToolsState) -> CommandLineToolsStatus {
        switch state {
        case .notInstalled: .notInstalled
        case .installed: .installed
        case .outdatedLauncher: .outdatedLauncher
        }
    }
}
