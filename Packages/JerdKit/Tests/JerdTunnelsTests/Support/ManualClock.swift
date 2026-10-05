import Foundation
import JerdTunnels
import os

/// A clock that moves only when a test calls `advance(by:)`. Sleepers wake in deadline order.
/// `waitForSleeper(_:)` resumes when a matching sleeper starts, so no test waits for real time.
final class ManualClock: TunnelClocking {
    private struct Sleeper {
        let id: UUID
        let deadline: ContinuousClock.Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct Watcher {
        let delay: Duration
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var now = ContinuousClock.now
        var sleepers: [Sleeper] = []
        var cancelled: Set<UUID> = []
        var watchers: [Watcher] = []

        var pendingDelays: [Duration] { sleepers.map { now.duration(to: $0.deadline) }.sorted() }

        /// Removes and returns the watchers whose sleeper now exists.
        mutating func satisfiedWatchers() -> [Watcher] {
            let delays = pendingDelays
            let due = watchers.filter { delays.contains($0.delay) }
            watchers.removeAll { delays.contains($0.delay) }
            return due
        }
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var now: ContinuousClock.Instant { state.withLock(\.now) }

    /// The remaining time of each sleeper, shortest first.
    var pendingDelays: [Duration] { state.withLock(\.pendingDelays) }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let (cancelledEarly, due) = state.withLock { state -> (Bool, [Watcher]) in
                    guard !state.cancelled.contains(id) else { return (true, []) }
                    state.sleepers.append(Sleeper(id: id, deadline: state.now + duration, continuation: continuation))
                    return (false, state.satisfiedWatchers())
                }
                if cancelledEarly { continuation.resume(throwing: CancellationError()) }
                for watcher in due { watcher.continuation.resume() }
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
        let (due, watchers) = state.withLock { state -> ([Sleeper], [Watcher]) in
            state.now += duration
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }.sorted { $0.deadline < $1.deadline }
            state.sleepers.removeAll { $0.deadline <= now }
            return (due, state.satisfiedWatchers())
        }
        for sleeper in due { sleeper.continuation.resume() }
        for watcher in watchers { watcher.continuation.resume() }
    }

    /// Returns when a sleeper with exactly `delay` left exists: at once, or when it starts.
    func waitForSleeper(_ delay: Duration) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = state.withLock { state -> Bool in
                guard !state.pendingDelays.contains(delay) else { return true }
                state.watchers.append(Watcher(delay: delay, continuation: continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}
