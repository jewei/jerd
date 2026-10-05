/// How collecting an exited connector ended.
package enum TunnelReap: Equatable, Sendable {
    /// The connector is gone and its output shows no token rejection.
    case stopped
    /// The connector is gone, and its last output shows a token rejection.
    case stoppedAfterTokenRejection
    /// The connector group could not be stopped. Jerd keeps it.
    case notStopped(String)
}
