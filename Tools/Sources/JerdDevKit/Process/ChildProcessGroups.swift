import Darwin
import os

/// The process groups of the running children. The runner adds a group when it starts a child and
/// removes it when it reaps the child; the signal forwarder signals every group that is still here.
/// Each change and each signal happens under one lock, so a signal never reaches a reaped, reused ID.
final class ChildProcessGroups: Sendable {
    private struct State {
        var groups: Set<pid_t> = []
        var isStopping = false
    }

    /// The groups of the live runner. `SignalForwarder.installLive` signals these groups.
    static let shared = ChildProcessGroups()

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let sendSignal: @Sendable (pid_t, Int32) -> Void

    /// - Parameter sendSignal: Sends a signal to a process group. Tests record the calls.
    init(sendSignal: @escaping @Sendable (pid_t, Int32) -> Void = { ChildProcess.signalGroup($0, $1) }) {
        self.sendSignal = sendSignal
    }

    /// Starts a child with `start` and adds its group. After an interrupt it starts nothing, so a
    /// stopping `./dev` cannot begin its next step.
    func start(commandLine: String, _ start: @Sendable () throws -> pid_t) throws -> pid_t {
        try state.withLock { state in
            guard !state.isStopping else {
                throw InvocationFailure.launchFailed(
                    commandLine: commandLine, reason: "./dev is stopping after a signal.")
            }
            let group = try start()
            state.groups.insert(group)
            return group
        }
    }

    /// Removes the group and reaps its exited leader in one step.
    func finish(_ group: pid_t, reap: @Sendable () -> Void) {
        state.withLock { state in
            state.groups.remove(group)
            reap()
        }
    }

    /// Sends the signal to every running group. With `stopStarting`, no new child starts after this.
    func signalAll(_ signal: Int32, stopStarting: Bool = false) {
        state.withLock { state in
            if stopStarting { state.isStopping = true }
            state.groups.forEach { sendSignal($0, signal) }
        }
    }

    var running: Set<pid_t> {
        state.withLock { $0.groups }
    }
}
