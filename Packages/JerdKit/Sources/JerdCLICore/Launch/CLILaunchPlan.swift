/// The exact program that replaces the launcher: the PHP executable, its argument vector, and the
/// environment entries that the launcher sets before `execv`. Other variables pass through unchanged.
public struct CLILaunchPlan: Equatable, Sendable {
    /// The absolute PHP executable path.
    public let executable: String
    /// The complete argument vector. `arguments[0]` is the PHP executable path.
    public let arguments: [String]
    /// Variables that the launcher sets (and overwrites) in its own environment.
    public let environmentChanges: [String: String]

    public init(executable: String, arguments: [String], environmentChanges: [String: String]) {
        self.executable = executable
        self.arguments = arguments
        self.environmentChanges = environmentChanges
    }

    /// The environment that PHP sees when the launcher starts with `environment`.
    public func environment(applyingTo environment: [String: String]) -> [String: String] {
        environment.merging(environmentChanges) { _, change in change }
    }
}
