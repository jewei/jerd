import Darwin
import JerdProcess
import os

/// Simulated kernel answers for run records: a saved process is either alive or gone.
final class FakeSystem: Sendable {
    private let alive = OSAllocatedUnfairLock(initialState: false)

    /// When true, every saved process counts as running, so its record blocks a start.
    func setSavedProcessesAlive(_ value: Bool) { alive.withLock { $0 = value } }

    var observer: ProcessObserver {
        ProcessObserver(
            match: { [alive] _ in alive.withLock { $0 } ? .running : .exited },
            isGone: { [alive] _ in !alive.withLock { $0 } },
            groups: ProcessGroupInspector(list: { _, _ in (0, 0) }, liveness: { _ in false }),
            auditedSignalsSupported: false)
    }

    /// A recorder that captures a fixed identity for any PID, owned by the current user.
    static let recorder = ActiveRunRecorder(capture: { pid in
        ProcessIdentity(
            processID: pid, userID: geteuid(), startedSeconds: 100, startedMicroseconds: 1, bootSeconds: 10,
            executable: "/fake/bin/server", auditWords: nil, bootSessionID: nil)
    })
}
