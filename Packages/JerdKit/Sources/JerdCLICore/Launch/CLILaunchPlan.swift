/// The exact program that replaces the launcher: the PHP executable, its argument vector, and its
/// complete environment, all as the bytes that `execve` gets.
package struct CLILaunchPlan: Equatable, Sendable {
    /// The absolute PHP executable path.
    package let executable: String
    /// The complete argument vector. `arguments[0]` is the PHP executable path.
    package let arguments: [[UInt8]]
    /// The complete environment: the launcher's entries with the planned variables set.
    package let environment: CLIEnvironment

    package init(executable: String, arguments: [[UInt8]], environment: CLIEnvironment) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}
