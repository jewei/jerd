/// Everything that the reconnect rules remember about one tunnel. Only `TunnelReconnectPolicy.reduce` changes it.
package struct TunnelLifecycle: Equatable, Sendable {
    /// The state that the app shows.
    package var state: TunnelState
    /// The current Connect request. Nil when the user does not want a connection.
    package var generation: TunnelGeneration?
    /// Start a new connector after an unexpected exit.
    package var restartOnFailure: Bool
    /// A connector of this generation was launched once. Before that, every failure needs the user.
    package var hasLaunched = false
    /// A connector of this generation was ready once. It decides "Connecting…" or "Reconnecting…".
    package var hasConnected = false
    /// Retries since the last stable connection. It selects the backoff delay.
    package var retries = 0
    /// When the current run of ready checks began. Nil after any check that was not ready.
    package var connectedSince: ContinuousClock.Instant?
    /// When the current connector was launched. Nil after its first ready check.
    package var launchedAt: ContinuousClock.Instant?
    /// Starts in a row that failed: a transient launch failure, or an exit soon after the launch
    /// before any ready check. A ready check sets it to 0.
    package var failedStarts = 0

    package init(state: TunnelState = .stopped, generation: TunnelGeneration? = nil, restartOnFailure: Bool = false) {
        self.state = state
        self.generation = generation
        self.restartOnFailure = restartOnFailure
    }

    /// No connector and no request.
    package static let idle = TunnelLifecycle()

    /// The state while Jerd waits for readiness: the first connection, or a lost one.
    var waitingState: TunnelState { hasConnected ? .reconnecting : .connecting }

    /// Ends the generation with a message for the user.
    mutating func fail(_ message: String) -> TunnelStep {
        state = .failed(message)
        generation = nil
        connectedSince = nil
        launchedAt = nil
        return .idle
    }
}
