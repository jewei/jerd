/// Replaces the current process with the planned PHP command. Tests record the plan instead.
package protocol ProcessImageReplacing: Sendable {
    /// Calls `execve` with the plan's bytes. Returns only when `execve` fails, with the `errno` value.
    func replace(with plan: CLILaunchPlan) -> Int32
}
