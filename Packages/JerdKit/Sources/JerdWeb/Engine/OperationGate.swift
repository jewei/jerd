import os

/// A first-in, first-out lock for one operation at a time across actor suspension points.
///
/// It replaces a Bool flag with sleep loops (spec B 7.2.1): a waiter suspends without polling
/// and `leave()` hands the lock to the next waiter directly.
final class OperationGate: Sendable {
    private struct State {
        var busy = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// True while an operation holds the gate.
    var isBusy: Bool { state.withLock { $0.busy } }

    /// Takes the gate when it is free. Returns false (and takes nothing) when it is busy.
    func tryEnter() -> Bool {
        state.withLock { state in
            guard !state.busy else { return false }
            state.busy = true
            return true
        }
    }

    /// Waits for the gate in arrival order.
    func enter() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let free = state.withLock { state in
                guard state.busy else {
                    state.busy = true
                    return true
                }
                state.waiters.append(continuation)
                return false
            }
            if free { continuation.resume() }
        }
    }

    /// Releases the gate, or passes it to the first waiter.
    func leave() {
        let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard !state.waiters.isEmpty else {
                state.busy = false
                return nil
            }
            return state.waiters.removeFirst()
        }
        next?.resume()
    }
}
