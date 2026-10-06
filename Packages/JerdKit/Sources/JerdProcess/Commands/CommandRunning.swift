/// Runs one short command to completion. Managers depend on this role so that tests can use a fake.
public protocol CommandRunning: Sendable {
    /// Runs `request` and returns its status and output. A non-zero status is not an error.
    /// - Throws: `.timedOut` after `timeout`, `CancellationError` when the task is cancelled,
    ///   `.processFailed` with the PID when the command survives its cleanup, or a start error.
    func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult
}

extension CommandRunning {
    /// Runs `request` with the default timeout of 15 seconds.
    public func run(_ request: ProcessRequest) async throws -> CommandResult {
        try await run(request, timeout: CommandRunner.defaultTimeout)
    }
}
