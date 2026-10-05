/// The one piece of work that the supervisor runs next for a tunnel. Only one step runs at a time.
package enum TunnelStep: Equatable, Sendable {
    /// Nothing to do: the generation ended, or the event was stale.
    case idle
    /// Launch a connector now.
    case launch
    /// Wait, then check readiness.
    case check(after: Duration)
    /// Wait for the backoff delay, then launch a new connector.
    case relaunch(after: Duration)
    /// Collect the connector that exited, then report `.reaped`.
    case reap
    /// Stop the connector gracefully because of a fatal problem, then report `.disconnected`.
    case disconnect(TunnelFatalReason)
}

/// The result of one reduction: the next lifecycle and the step to run.
package struct TunnelTransition: Equatable, Sendable {
    package let lifecycle: TunnelLifecycle
    package let step: TunnelStep

    package init(_ lifecycle: TunnelLifecycle, _ step: TunnelStep) {
        self.lifecycle = lifecycle
        self.step = step
    }
}
