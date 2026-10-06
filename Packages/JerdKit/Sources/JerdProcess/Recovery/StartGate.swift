import Darwin
import Foundation
import JerdFoundation

/// Blocks a start while a process from an earlier run may still use the service data.
///
/// The check requires the service lock (the type system enforces it), so two Jerd processes
/// cannot race on one record.
public struct StartGate: Sendable {
    private let observer: ProcessObserver

    public init(observer: ProcessObserver = .system) { self.observer = observer }

    /// Allows a start when no record exists, or deletes a stale record and then allows it.
    /// - Throws: `.corrupt` for an unreadable record, `.unavailable` while a saved process may live.
    public func requireStopped(_ location: RecordLocation, holding lock: InstanceLock) throws -> StartClearance {
        try ActiveRunRecordFile.requireHeld(lock, for: location)
        guard FileProbe.presence(at: location.recordFile).mayExist else {
            return StartClearance(location: location, lock: lock)
        }
        try requireNoLiveRecord(location)
        try ActiveRunRecordFile.remove(location, holding: lock)
        return StartClearance(location: location, lock: lock)
    }

    /// Refuses at once when the record of `location` names a process that may still live. It
    /// needs no lock and changes no file, so a start can run it before its port checks: after a
    /// crash the earlier process still listens, and the user must see recovery, not "port
    /// occupied" (review final-domain-r1 M1). A stale record stays for the locked check.
    /// - Throws: `.corrupt` for an unreadable record, `.unavailable` while a saved process may live.
    public func requireNoLiveRecord(_ location: RecordLocation) throws {
        guard FileProbe.presence(at: location.recordFile).mayExist else { return }
        let record = try ActiveRunRecordFile.read(location.recordFile)
        guard RecoveryClassifier.isStale(record, observer.observe(record)) else {
            throw Self.needsInspection(record.processID)
        }
    }

    /// The refusal while a saved process may still use the service data.
    private static func needsInspection(_ processID: pid_t) -> JerdError {
        .unavailable(
            "A previous service process needs inspection (PID \(processID)). "
                + "Open Advanced → Process recovery. No process was signalled.")
    }
}
