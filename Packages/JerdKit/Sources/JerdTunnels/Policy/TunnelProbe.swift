/// What one readiness check found.
package enum TunnelProbe: Equatable, Sendable {
    /// The connector's `/ready` endpoint answered 200: at least one edge connection.
    case ready
    /// The connector runs but is not ready, or the check could not finish.
    case waiting
    /// The connector process exited.
    case exited
    /// The connector's output shows that Cloudflare rejected the token.
    case tokenRejected
    /// The connector listens on something other than its loopback metrics port.
    case unexpectedListener
}
