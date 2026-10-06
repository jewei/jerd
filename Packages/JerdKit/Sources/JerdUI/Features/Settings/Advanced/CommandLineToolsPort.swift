/// Whether the `php`, `composer`, and `laravel` commands are installed for zsh.
public enum CommandLineToolsState: Equatable, Sendable {
    case installed
    case notInstalled
    /// The commands exist, but an older Jerd installed them, or the PATH block is missing.
    case outdated
}

/// Installs the command-line tools. JerdLive implements it with `ShellSetupInstaller` from
/// JerdCLICore; `install()` returns the report lines of `ShellSetupReport.summary`.
public protocol CommandLineToolsPort: Sendable {
    func state() async -> CommandLineToolsState
    /// Installs the launcher and the PATH block. Nothing changes when a preflight check fails.
    func install() async throws -> [String]
}
