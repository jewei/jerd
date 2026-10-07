/// Runs external commands. `ProcessRunner` is the live type; tests use a recording fake.
protocol ProcessRunning: Sendable {
    /// Runs the command to its end. Throws `InvocationFailure` only when the command cannot start.
    /// A non-zero exit status and a passed time limit are part of the result.
    func run(_ invocation: Invocation, output: OutputMode) async throws -> InvocationResult
}

extension ProcessRunning {
    /// Runs the command and throws `InvocationFailure` when it did not succeed.
    @discardableResult
    func runChecked(_ invocation: Invocation, output: OutputMode) async throws -> InvocationResult {
        try await run(invocation, output: output).checked()
    }
}
