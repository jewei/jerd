import Darwin
import Dispatch
import os

/// A one-shot "process exited" event from a kernel process source, so waits need no polling.
///
/// Create the event before the last state check: an exit after the check then fires the source,
/// and an exit before it is seen by the check.
final class ExitEvent: Sendable {
    private struct Waiter: Sendable {
        var released = false
        var exitSeen = false
        var continuation: CheckedContinuation<Void, Never>?
    }

    private let source: any DispatchSourceProcess
    private let waiter = OSAllocatedUnfairLock(initialState: Waiter())

    init(pid: pid_t) {
        source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in self?.release(exit: true) }
        source.resume()
    }

    deinit { source.cancel() }

    /// True after the kernel reported the exit. The child can need a moment more to become waitable.
    var exitSeen: Bool { waiter.withLock { $0.exitSeen } }

    /// Returns when the process exits or the calling task is cancelled.
    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let released = waiter.withLock { state in
                    if !state.released { state.continuation = continuation }
                    return state.released
                }
                if released { continuation.resume() }
            }
        } onCancel: {
            release(exit: false)
        }
    }

    private func release(exit: Bool) {
        let continuation = waiter.withLock { state in
            state.released = true
            state.exitSeen = state.exitSeen || exit
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume()
    }
}
