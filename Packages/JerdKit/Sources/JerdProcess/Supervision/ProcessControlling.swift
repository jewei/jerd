import Darwin

/// Starts, watches, and stops owned long-running processes. Managers depend on this role so
/// that tests can use a fake.
public protocol ProcessControlling: Sendable {
    /// Starts the request in a new process group with `log` as its output. Returns its token.
    func start(_ request: ProcessRequest, log: ProcessLogFile) async throws -> ProcessToken
    /// The leader state, read without reaping.
    func state(of token: ProcessToken) async -> ProcessState
    /// The leader PID while Jerd owns it: running, or exited and not yet reaped.
    func processID(of token: ProcessToken) async -> pid_t?
    /// Waits until the leader exits or the timeout passes, without polling. Returns the state then.
    func waitForExit(of token: ProcessToken, timeout: Duration) async -> ProcessState
    /// Stops the group with the policy. Concurrent stops of one token share one result.
    func stop(_ token: ProcessToken, policy: StopPolicy) async -> StopOutcome
    /// Stops every owned group concurrently and returns each result.
    func stopAll(policy: StopPolicy) async -> [ProcessToken: StopOutcome]
}
