/// A part of Jerd that the staged quit stops: a feature model or one of its parts.
@MainActor
public protocol ShutdownParticipant: AnyObject {
    var shutdownPhase: ShutdownPhase { get }
    /// The banner message while this participant stops. Defaults to the phase message.
    var shutdownMessage: String { get }
    /// Where the window goes when this participant cannot stop. Defaults to the phase.
    var shutdownFailureDestination: Destination { get }
    /// Stops gracefully. Returns false when a service could not stop safely; it then keeps the
    /// process, its record, and its data lock.
    func shutdown() async -> Bool
    /// Makes the participant usable again after a cancelled quit, for example to retry Stop.
    func resumeAfterCancelledQuit()
}

extension ShutdownParticipant {
    public var shutdownMessage: String { shutdownPhase.message }
    public var shutdownFailureDestination: Destination { shutdownPhase.failureDestination }
}
