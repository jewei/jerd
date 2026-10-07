/// The facts from which `CLILaunchPlanner` builds a launch plan. The launcher collects them.
struct CLILaunchRequest: Equatable, Sendable {
    let command: CLICommand
    /// The PHP CLI executable of the selected runtime.
    let phpExecutable: String
    /// `["-c", <INI path>]`, or empty when the user chose the INI.
    let iniArguments: [String]
    /// The Composer or Laravel installer script. Nil for `php`.
    let companionScript: String?
    /// The exact user argument bytes, without `argv[0]`.
    let userArguments: [[UInt8]]
    /// The launcher's own environment, as raw entries.
    let environment: CLIEnvironment
    /// Variables that the INI decision adds, for example `PHP_INI_SCAN_DIR`.
    let iniEnvironment: [String: String]
    /// Jerd's `bin` folder with the `php`, `composer`, and `laravel` links.
    let binDirectory: String
}
