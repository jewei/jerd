/// The one piece of work that the supervisor runs next for a tunnel. Only one step runs at a time.
package enum TunnelStep: Equatable, Sendable {
    /// Nothing to do: the generation ended, or the event was stale.
    case idle
    /// Wait, then launch a connector: at once after Connect, or after the backoff delay.
    case launch(after: Duration)
    /// Wait, then check readiness.
    case check(after: Duration)
    /// Collect the connector that exited, then report `.reaped`.
    case reap
    /// Stop the connector gracefully because of a fatal problem, then report `.disconnected`.
    case disconnect(TunnelFatalReason)
}
