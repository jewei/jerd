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
