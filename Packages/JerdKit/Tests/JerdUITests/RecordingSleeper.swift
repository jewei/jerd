import JerdUI
import os

/// Records each requested sleep and returns at once for the first `allowedSleeps` calls; later
/// calls wait until their task is cancelled. Tests count ticks without real time.
final class RecordingSleeper: Sleeping {
    private let state: OSAllocatedUnfairLock<(durations: [Duration], allowed: Int)>

    init(allowedSleeps: Int) {
        state = OSAllocatedUnfairLock(initialState: ([], allowedSleeps))
    }

    var durations: [Duration] { state.withLock { $0.durations } }

    /// Lets more sleeps return at once.
    func allow(_ count: Int) {
        state.withLock { $0.allowed += count }
    }

    func sleep(for duration: Duration) async throws {
        state.withLock { $0.durations.append(duration) }
        while true {
            let mayReturn = state.withLock { state -> Bool in
                guard state.allowed > 0 else { return false }
                state.allowed -= 1
                return true
            }
            if mayReturn { return }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}
