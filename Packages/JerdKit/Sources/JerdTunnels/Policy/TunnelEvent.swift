/// Something that happened to one tunnel. The supervisor reports it; `TunnelReconnectPolicy` decides what follows.
package enum TunnelEvent: Equatable, Sendable {
    /// The user selected Connect (or Jerd connects at startup). A new generation begins.
    case connectRequested(TunnelGeneration, restartOnFailure: Bool)
    /// The user selected Stop, or Jerd quits. The current generation ends.
    case stopRequested
    /// The graceful stop finished. A message means that the connector still runs.
    case stopFinished(error: String?)
    /// A result of work that belongs to one generation.
    case progress(TunnelGeneration, TunnelProgress)
}

/// The result of one step of connector work.
package enum TunnelProgress: Equatable, Sendable {
    /// A connector process runs and Jerd owns it.
    case launched
    /// No connector could be launched.
    case launchFailed(TunnelFailure)
    /// One readiness check finished.
    case probed(TunnelProbe)
    /// Jerd collected a connector that exited by itself.
    case reaped(TunnelReap)
    /// Jerd stopped a connector after a fatal problem. A message means that the stop failed.
    case disconnected(TunnelFatalReason, stopError: String?)
}

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

/// How collecting an exited connector ended.
package enum TunnelReap: Equatable, Sendable {
    /// The connector is gone and its output shows no token rejection.
    case stopped
    /// The connector is gone, and its last output shows a token rejection.
    case stoppedAfterTokenRejection
    /// The connector group could not be stopped. Jerd keeps it.
    case notStopped(String)
}

/// A problem that ends the current generation and needs the user.
package enum TunnelFatalReason: Equatable, Sendable {
    case tokenRejected
    case unexpectedListener

    /// The state message, given the result of the graceful stop that follows the problem.
    package func message(stopError: String?) -> String {
        switch self {
        case .tokenRejected:
            stopError.map { TunnelMessage.tokenRejectedPrefix + $0 } ?? TunnelMessage.tokenRejected
        case .unexpectedListener:
            // A failed stop keeps the connector owned, so an explicit Stop can retry it.
            TunnelMessage.unexpectedListener
        }
    }
}
