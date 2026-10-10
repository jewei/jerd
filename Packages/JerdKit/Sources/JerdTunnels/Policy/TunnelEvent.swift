/// Something that happened to one tunnel. The supervisor reports it; `TunnelReconnectPolicy` decides what follows.
package enum TunnelEvent: Equatable, Sendable {
    /// The user selected Connect (or Jerd connects at startup). A new generation begins.
    case connectRequested(TunnelGeneration, restartOnFailure: Bool)
    /// The user selected Stop, or Jerd quits. The current generation ends.
    case stopRequested
    /// The graceful stop finished. An error means that the connector still runs. A reason, after
    /// a stop that Jerd made on its own, tells the user why the tunnel stopped.
    case stopFinished(error: String?, reason: String? = nil)
    /// A result of work that belongs to one generation.
    case progress(TunnelGeneration, TunnelProgress)
}
