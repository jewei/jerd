import JerdUI
import JerdUIFixtures

/// A shutdown participant that records its calls and can wait before it answers.
@MainActor
final class RecordingParticipant: ShutdownParticipant {
    let shutdownPhase: ShutdownPhase
    let stops: Bool
    let journal: CallJournal
    var destination: Destination?
    /// While true, `shutdown()` waits.
    var isBlocked = false
    private(set) var stopCount = 0
    private(set) var resumeCount = 0

    init(phase: ShutdownPhase, stops: Bool, journal: CallJournal) {
        self.shutdownPhase = phase
        self.stops = stops
        self.journal = journal
    }

    var shutdownFailureDestination: Destination { destination ?? shutdownPhase.failureDestination }

    func shutdown() async -> Bool {
        stopCount += 1
        journal.record("\(shutdownPhase).stop")
        while isBlocked {
            await Task.yield()
        }
        return stops
    }

    func resumeAfterCancelledQuit() {
        resumeCount += 1
    }
}
