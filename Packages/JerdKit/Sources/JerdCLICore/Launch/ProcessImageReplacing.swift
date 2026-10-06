/// Replaces the current process with the planned PHP command. Tests record the plan instead.
public protocol ProcessImageReplacing: Sendable {
    /// Sets the planned environment entries and calls `execv`. Returns only when `execv` fails,
    /// with the `errno` value.
    func replace(with plan: CLILaunchPlan) -> Int32
}
