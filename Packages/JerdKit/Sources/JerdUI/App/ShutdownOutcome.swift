/// The result of a staged quit.
public enum ShutdownOutcome: Equatable, Sendable {
    /// Every stage stopped. The app can terminate.
    case stopped
    /// A stage could not stop safely. The quit is cancelled and Jerd stays open.
    case cancelled(phase: ShutdownPhase, message: String, destination: Destination)
}
