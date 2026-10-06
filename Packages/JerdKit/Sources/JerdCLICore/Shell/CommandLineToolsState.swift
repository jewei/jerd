/// Whether the `php`, `composer`, and `laravel` commands are set up, for the app to show.
public enum CommandLineToolsState: Equatable, Sendable {
    /// `bin/JerdCLI`, a command link, or the PATH block in the zsh startup files is missing.
    case notInstalled
    /// Everything is in place, and `bin/JerdCLI` is the launcher of this app.
    case installed
    /// Everything is in place, but `bin/JerdCLI` differs from the launcher of this app.
    case outdatedLauncher

    /// One line for the user.
    public var summary: String {
        switch self {
        case .notInstalled: "The php, composer, and laravel commands are not installed."
        case .installed: "The php, composer, and laravel commands are installed."
        case .outdatedLauncher: "The php, composer, and laravel commands use an older Jerd launcher."
        }
    }
}
