/// The facts from which `CLILaunchPlanner` builds a launch plan. The launcher collects them.
public struct CLILaunchRequest: Equatable, Sendable {
    public let command: CLICommand
    /// The PHP CLI executable of the selected runtime.
    public let phpExecutable: String
    /// `["-c", <INI path>]`, or empty when the user chose the INI.
    public let iniArguments: [String]
    /// The Composer or Laravel installer script. Nil for `php`.
    public let companionScript: String?
    /// The user arguments, without `argv[0]`.
    public let userArguments: [String]
    /// The launcher's own environment.
    public let environment: [String: String]
    /// Variables that the INI decision adds, for example `PHP_INI_SCAN_DIR`.
    public let iniEnvironment: [String: String]
    /// Jerd's `bin` folder with the `php`, `composer`, and `laravel` links.
    public let binDirectory: String

    public init(
        command: CLICommand, phpExecutable: String, iniArguments: [String], companionScript: String?,
        userArguments: [String], environment: [String: String], iniEnvironment: [String: String],
        binDirectory: String
    ) {
        self.command = command
        self.phpExecutable = phpExecutable
        self.iniArguments = iniArguments
        self.companionScript = companionScript
        self.userArguments = userArguments
        self.environment = environment
        self.iniEnvironment = iniEnvironment
        self.binDirectory = binDirectory
    }
}
