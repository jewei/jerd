import os

/// A `pause` for `HelperRegistration` that really suspends until the test opens it, so a test can
/// start other calls in the middle of a restart.
final class PauseGate: Sendable {
    private struct State {
        var isOpen = false
        var paused = 0
        var sleepers: [CheckedContinuation<Void, Never>] = []
        var watchers: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func pause(_ duration: Duration) async {
        await withCheckedContinuation { continuation in
            let (resume, watchers) = state.withLock { current -> (Bool, [CheckedContinuation<Void, Never>]) in
                current.paused += 1
                defer { current.watchers = [] }
                if !current.isOpen { current.sleepers.append(continuation) }
                return (current.isOpen, current.watchers)
            }
            watchers.forEach { $0.resume() }
            if resume { continuation.resume() }
        }
    }

    /// Returns once a pause started.
    func waitUntilPaused() async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { current -> Bool in
                if current.paused > 0 { return true }
                current.watchers.append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }

    /// Ends every pause, now and later.
    func open() {
        let sleepers = state.withLock { current -> [CheckedContinuation<Void, Never>] in
            current.isOpen = true
            defer { current.sleepers = [] }
            return current.sleepers
        }
        sleepers.forEach { $0.resume() }
    }
}
