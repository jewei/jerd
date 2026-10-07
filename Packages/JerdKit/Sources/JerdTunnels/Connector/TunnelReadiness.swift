/// What a readiness check of a running connector found.
public enum TunnelReadiness: Equatable, Sendable {
    /// `/ready` answered 200: cloudflared has at least one edge connection.
    case ready
    /// The metrics listener is not up yet, or `/ready` did not answer 200.
    case waiting
    /// The connector listens somewhere other than `127.0.0.1:<metricsPort>`, or another process
    /// shares the metrics port.
    case unexpectedListener
}
