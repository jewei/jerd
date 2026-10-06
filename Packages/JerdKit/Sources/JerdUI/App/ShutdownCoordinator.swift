import Observation

/// Runs the staged quit: each participant stops in phase order. When a participant cannot stop
/// safely, the quit is cancelled, every participant that already started its stop resumes,
/// and the outcome names the exact message and the destination of the failed stage.
@MainActor
@Observable
public final class ShutdownCoordinator {
    /// The state of the quit.
    public enum State: Equatable, Sendable {
        case idle
        /// A stage runs. The message shows in the operation banner.
        case stopping(String)
        /// Every stage stopped. The app terminates.
        case finished
    }

    public private(set) var state: State = .idle

    public init() {}

    /// The decision for a new quit request. Only the first request starts a quit; a request
    /// during a quit is cancelled at once, so no request waits for a reply that never comes.
    public var replyToNewRequest: TerminationReply {
        switch state {
        case .idle: .later
        case .stopping: .cancel
        case .finished: .now
        }
    }

    /// The banner message while a quit runs.
    public var message: String? {
        if case .stopping(let message) = state { return message }
        return nil
    }

    /// Stops every participant in phase order. Participants with the same phase keep their order.
    public func run(_ participants: [any ShutdownParticipant]) async -> ShutdownOutcome {
        guard state == .idle else { return .stopped }
        let ordered = participants.enumerated().sorted {
            ($0.element.shutdownPhase, $0.offset) < ($1.element.shutdownPhase, $1.offset)
        }.map(\.element)
        var started: [any ShutdownParticipant] = []
        for participant in ordered {
            state = .stopping(participant.shutdownMessage)
            started.append(participant)
            if await participant.shutdown() { continue }
            for resumed in started {
                resumed.resumeAfterCancelledQuit()
            }
            state = .idle
            return .cancelled(
                phase: participant.shutdownPhase, message: participant.shutdownPhase.failureMessage,
                destination: participant.shutdownFailureDestination)
        }
        state = .finished
        return .stopped
    }
}
