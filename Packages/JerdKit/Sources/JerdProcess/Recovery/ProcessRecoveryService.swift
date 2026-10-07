import Darwin
import Foundation
import JerdFoundation

/// Inspects saved run records and stops verified orphan processes gracefully, on user request.
///
/// It reads only the fixed record locations of a `DataLayout` and never accepts a PID, an
/// executable, a signal, or a path from the caller. It never sends `SIGKILL`, and it deletes a
/// record only while it holds the record's lock. One recovery runs at a time.
public actor ProcessRecoveryService {
    /// Captures the identity of a PID.
    public typealias Capture = @Sendable (pid_t) throws -> ProcessIdentity

    private let layout: DataLayout
    let observer: ProcessObserver
    let signaller: AuditedSignaller
    let capture: Capture
    let pollInterval: Duration
    private var busy = false

    public init(
        layout: DataLayout, observer: ProcessObserver = .system, signaller: AuditedSignaller = .system,
        capture: @escaping Capture = ProcessIdentity.capture, pollInterval: Duration = .milliseconds(100)
    ) {
        self.layout = layout
        self.observer = observer
        self.signaller = signaller
        self.capture = capture
        self.pollInterval = pollInterval
    }

    /// One row per record or per unreadable folder, in a fixed order: Mail, Storage, Database,
    /// Tunnel, Web, then by instance ID.
    public func inspect() -> [RecoveryFinding] {
        RecordLocationScanner.scan(layout).map { entry in
            switch entry {
            case .failure(let id, let title, let message):
                return RecoveryFinding(id: id, title: title, detail: message, state: .manual)
            case .location(let location):
                let title = RecordLocationScanner.title(location)
                do {
                    let record = try ActiveRunRecordFile.read(location.recordFile)
                    let verdict = RecoveryClassifier.classify(record, observer.observe(record))
                    return RecoveryFinding(id: location.id, title: title, detail: verdict.detail, state: verdict.state)
                } catch {
                    return RecoveryFinding(
                        id: location.id, title: title, detail: FailureDetail.describe(error), state: .manual)
                }
            }
        }
    }

    /// Clears a stale record, or requests a graceful stop of a verified orphan and waits for it.
    /// - Throws: `.unavailable` with the reason when recovery is not safe. The record stays.
    public func recover(_ id: String, timeout: Duration = .seconds(30)) async throws {
        guard !busy else { throw JerdError.unavailable("Wait for process recovery to finish.") }
        busy = true
        defer { busy = false }
        guard let location = RecordLocationScanner.locations(layout).first(where: { $0.id == id }) else {
            throw JerdError.unavailable("The process record is no longer present. Inspect again.")
        }
        let lock = try InstanceLock.acquire(
            at: location.lockFile,
            messages: .init(
                unavailable: "Cannot lock the saved service.", busy: "Another Jerd process is using this service."))
        defer { lock.release() }
        var record = try ActiveRunRecordFile.read(location.recordFile)
        let observation = observer.observe(record)
        let verdict = RecoveryClassifier.classify(record, observation)
        guard verdict.state.canRecover else { throw JerdError.unavailable(verdict.detail) }
        if verdict.state == .recoverable {
            try requestStop(&record, observation, at: location, holding: lock)
            try await waitUntilStale(record, deadline: ContinuousClock.now + timeout)
        }
        try ActiveRunRecordFile.remove(location, holding: lock)
    }
}
