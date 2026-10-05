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
        let record = try ActiveRunRecordFile.read(location.recordFile)
        guard RecoveryClassifier.isStale(record, observer.observe(record)) else {
            throw JerdError.unavailable(
                "A previous service process needs inspection (PID \(record.processID)). "
                    + "Open Advanced → Process recovery. No process was signalled.")
        }
        try ActiveRunRecordFile.remove(location, holding: lock)
        return StartClearance(location: location, lock: lock)
    }
}
