import Foundation
import JerdTunnels
import os

/// A clock that moves only when a test calls `advance(by:)`. Sleepers wake in deadline order.
final class ManualClock: TunnelClocking {
    private struct Sleeper {
        let id: UUID
        let deadline: ContinuousClock.Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = ContinuousClock.now
        var sleepers: [Sleeper] = []
        var cancelled: Set<UUID> = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var now: ContinuousClock.Instant { state.withLock(\.now) }

    /// The remaining time of each sleeper, shortest first.
    var pendingDelays: [Duration] {
        state.withLock { state in state.sleepers.map { state.now.duration(to: $0.deadline) }.sorted() }
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let cancelledEarly = state.withLock { state in
                    guard !state.cancelled.contains(id) else { return true }
                    state.sleepers.append(Sleeper(id: id, deadline: state.now + duration, continuation: continuation))
                    return false
                }
                if cancelledEarly { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let sleeper = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                    state.cancelled.insert(id)
                    return nil
                }
                return state.sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and wakes every sleeper whose deadline passed.
    func advance(by duration: Duration) {
        let due = state.withLock { state -> [Sleeper] in
            state.now += duration
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }.sorted { $0.deadline < $1.deadline }
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// Waits until a sleeper with exactly `delay` left exists.
    func waitForSleeper(_ delay: Duration) async -> Bool {
        await eventually { pendingDelays.contains(delay) }
    }
}
