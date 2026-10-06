/// Whether the `php`, `composer`, and `laravel` commands are set up for zsh. The cases map one
/// to one to `JerdCLICore.CommandLineToolsState`; the other name keeps JerdLive, which imports
/// both modules, free of an ambiguous type name.
public enum CommandLineToolsStatus: Equatable, Sendable {
    /// The launcher, a command link, or the PATH block in the zsh startup files is missing.
    case notInstalled
    /// Everything is in place, and the launcher is the one of this app.
    case installed
    /// Everything is in place, but an older Jerd installed the launcher.
    case outdatedLauncher
}

/// Installs the command-line tools. JerdLive implements it with `ShellSetupInstaller` from
/// JerdCLICore: `status()` maps `state()`, and `install()` returns `ShellSetupReport.summary`.
public protocol CommandLineToolsPort: Sendable {
    func status() async -> CommandLineToolsStatus
    /// Installs the launcher and the PATH block. Nothing changes when a preflight check fails.
    func install() async throws -> [String]
}
