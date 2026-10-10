/// The timing and the pure rules of one connector's life: launch, readiness checks, backoff, and failures.
///
/// `reduce` is the only function that changes a `TunnelLifecycle`. It has no side effects: it returns
/// the next lifecycle and the one step that the supervisor must run next. A result of an older
/// generation changes nothing, so late work can never stop or relabel a newer connector.
public struct TunnelReconnectPolicy: Equatable, Sendable {
    /// 2, 5, 15, 30, then 60 seconds for every later retry.
    public static let standardRetryDelays: [Duration] = [
        .seconds(2), .seconds(5), .seconds(15), .seconds(30), .seconds(60),
    ]
    /// The production timing.
    public static let standard = TunnelReconnectPolicy()

    /// The time between two readiness checks of a running connector.
    public let checkInterval: Duration
    /// The backoff delays. The last one repeats.
    public let retryDelays: [Duration]
    /// How long a connection must stay ready before the backoff starts again at the first delay.
    public let stableConnection: Duration
    /// A connector that exits this soon after its launch, before any ready check, failed to start.
    public let quickExit: Duration
    /// After this many failed starts in a row, the retries stop and the user must act.
    public let failedStartLimit: Int

    /// An empty delay list becomes `[60 s]`. A failed-start limit below 1 becomes 1.
    public init(
        checkInterval: Duration = .seconds(5), retryDelays: [Duration] = standardRetryDelays,
        stableConnection: Duration = .seconds(30), quickExit: Duration = .seconds(15), failedStartLimit: Int = 5
    ) {
        self.checkInterval = checkInterval
        self.retryDelays = retryDelays.isEmpty ? [.seconds(60)] : retryDelays
        self.stableConnection = stableConnection
        self.quickExit = quickExit
        self.failedStartLimit = max(failedStartLimit, 1)
    }

    /// The next lifecycle and step after `event`, at time `now`.
    package func reduce(
        _ lifecycle: TunnelLifecycle, _ event: TunnelEvent, now: ContinuousClock.Instant
    ) -> TunnelTransition {
        switch event {
        case .connectRequested(let generation, let restartOnFailure):
            let next = TunnelLifecycle(state: .starting, generation: generation, restartOnFailure: restartOnFailure)
            return TunnelTransition(next, .launch(after: .zero))
        case .stopRequested:
            return TunnelTransition(TunnelLifecycle(state: .stopping), .idle)
        case .stopFinished(let error, let reason):
            return TunnelTransition(
                TunnelLifecycle(state: (error ?? reason).map(TunnelState.failed) ?? .stopped), .idle)
        case .progress(let generation, let progress):
            guard generation == lifecycle.generation else { return TunnelTransition(lifecycle, .idle) }
            var next = lifecycle
            let step = advance(&next, progress, now: now)
            return TunnelTransition(next, step)
        }
    }

    /// The backoff delay before retry number `retries + 1`.
    package func retryDelay(after retries: Int) -> Duration {
        retryDelays[min(max(retries, 0), retryDelays.count - 1)]
    }
}
