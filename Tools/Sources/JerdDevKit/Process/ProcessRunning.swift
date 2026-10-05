/// Runs external commands. `ProcessRunner` is the live type; tests use a recording fake.
public protocol ProcessRunning: Sendable {
    /// Runs the command to its end. Throws `InvocationFailure` only when the command cannot start
    /// or passes its time limit. A non-zero exit status is part of the result.
    func run(_ invocation: Invocation, output: OutputMode) async throws -> InvocationResult
}

extension ProcessRunning {
    /// Runs the command and throws `InvocationFailure.exited` when its exit status is not zero.
    @discardableResult
    func runChecked(_ invocation: Invocation, output: OutputMode) async throws -> InvocationResult {
        try await run(invocation, output: output).checked()
    }
}
