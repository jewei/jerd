import Foundation
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Shutdown coordinator")
@MainActor
struct ShutdownCoordinatorTests {
    /// One participant per failable phase, in a scrambled order.
    private func participants(failing: ShutdownPhase?, journal: CallJournal) -> [RecordingParticipant] {
        let phases: [ShutdownPhase] = [.webEnvironment, .mail, .tunnels, .databases, .runtimeWork, .storage, .siteWork]
        return phases.map { RecordingParticipant(phase: $0, stops: $0 != failing, journal: journal) }
    }

    @Test("Every stage stops in the fixed order, then the quit finishes")
    func stopsInOrder() async {
        let journal = CallJournal()
        let coordinator = ShutdownCoordinator()
        let all = participants(failing: nil, journal: journal)
        let outcome = await coordinator.start { all }?.value
        #expect(outcome == .stopped)
        #expect(coordinator.state == .finished)
        #expect(
            journal.entries == [
                "siteWork.stop", "runtimeWork.stop", "tunnels.stop", "storage.stop", "mail.stop", "databases.stop",
                "webEnvironment.stop",
            ])
    }

    @Test(
        "A failed stage cancels the quit with its exact message and destination",
        arguments: [
            (
                ShutdownPhase.tunnels, "A tunnel could not stop safely. Jerd will remain open. Retry Stop in Sites.",
                Destination.section(.sites)
            ),
            (
                .storage, "Storage could not stop safely. Jerd will remain open. Retry Stop in Storage.",
                .section(.storage)
            ),
            (
                .mail, "The mail service could not stop safely. Jerd will remain open. Retry Stop in Mail.",
                .section(.mail)
            ),
            (
                .databases,
                "A database service could not stop safely. Jerd will remain open. Check Databases and retry Stop.",
                .section(.databases)
            ),
        ])
    func failureCancels(phase: ShutdownPhase, message: String, destination: Destination) async {
        let journal = CallJournal()
        let coordinator = ShutdownCoordinator()
        let all = participants(failing: phase, journal: journal)
        let outcome = await coordinator.start { all }?.value
        #expect(outcome == .cancelled(phase: phase, message: message, destination: destination))
        #expect(coordinator.state == .idle)
        for participant in all {
            let started = participant.shutdownPhase <= phase
            #expect(participant.stopCount == (started ? 1 : 0))
            #expect(participant.resumeCount == (started ? 1 : 0))
        }
    }

    @Test("A participant can name a more exact failure destination")
    func participantDestination() async {
        let tunnel = SidebarSelection.tunnel(UUIDs.first)
        let participant = RecordingParticipant(phase: .tunnels, stops: false, journal: CallJournal())
        participant.destination = .item(tunnel)
        let outcome = await ShutdownCoordinator().start { [participant] }?.value
        #expect(
            outcome
                == .cancelled(
                    phase: .tunnels, message: ShutdownPhase.tunnels.failureMessage, destination: .item(tunnel)))
    }

    @Test("Only the first quit request starts a quit; later requests get an answer at once")
    func oneReplyPerRequest() async {
        let coordinator = ShutdownCoordinator()
        #expect(coordinator.replyToNewRequest == .later)
        let waiting = RecordingParticipant(phase: .storage, stops: true, journal: CallJournal())
        waiting.isBlocked = true
        let run = coordinator.start { [waiting] }
        await waitUntil { coordinator.message == ShutdownPhase.storage.message }
        #expect(coordinator.replyToNewRequest == .cancel)
        waiting.isBlocked = false
        #expect(await run?.value == .stopped)
        #expect(coordinator.replyToNewRequest == .now)
    }
}

enum UUIDs {
    static let first = UUID(uuidString: "00000000-0000-4000-8000-000000000001") ?? UUID()
}
