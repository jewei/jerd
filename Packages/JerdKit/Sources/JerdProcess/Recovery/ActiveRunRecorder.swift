import Darwin
import Foundation
import JerdFoundation

/// Saves the record of a child that was just started at a cleared location.
public struct ActiveRunRecorder: Sendable {
    /// Captures the identity of a PID.
    public typealias Capture = @Sendable (pid_t) throws -> ProcessIdentity

    private let capture: Capture

    public init(capture: @escaping Capture = ProcessIdentity.capture) { self.capture = capture }

    /// Writes the best evidence that is available, then reports a failed capture.
    ///
    /// A clearance allows a new record only: when a record already exists (for example from an
    /// earlier start with the same clearance whose process still runs), nothing is written and
    /// `.unavailable` is thrown, so the record of a live process is never replaced.
    ///
    /// - The full record when both identities are captured.
    /// - Without `controller` when Jerd cannot inspect itself: recovery then treats it as manual.
    /// - The fallback form (no `identity`) when the child cannot be captured, for example because
    ///   it already exited and left a child behind. The capture error is then thrown.
    public func record(
        processID: pid_t, runtimeID: String, gracefulSignal: Int32, clearance: StartClearance
    ) throws {
        guard clearance.isValid else {
            throw JerdError.invalid("Hold the lock of \(clearance.location.id) before saving its process record.")
        }
        let controller: ProcessIdentity?
        do {
            controller = try capture(getpid())
        } catch {
            // The child already runs, so it is still recorded. Without a controller identity,
            // recovery classifies the record as manual, which is the safe direction.
            controller = nil
        }
        let identity: ProcessIdentity
        do {
            identity = try capture(processID)
        } catch {
            try create(processID, runtimeID, nil, controller, gracefulSignal, clearance)
            throw error
        }
        guard identity.userID == geteuid() else {
            try create(processID, runtimeID, nil, controller, gracefulSignal, clearance)
            throw JerdError.invalid("The process belongs to another user.")
        }
        try create(processID, runtimeID, identity, controller, gracefulSignal, clearance)
    }

    private func create(
        _ pid: pid_t, _ runtimeID: String, _ identity: ProcessIdentity?, _ controller: ProcessIdentity?,
        _ signal: Int32, _ clearance: StartClearance
    ) throws {
        let record = ActiveRunRecord(
            processID: pid, runtimeID: runtimeID, identity: identity, controller: controller, gracefulSignal: signal)
        try ActiveRunRecordFile.create(record, at: clearance.location, holding: clearance.lock)
    }
}
