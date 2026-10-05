import Darwin
import Foundation
import JerdFoundation
import JerdProcess

/// The run records of web processes: `environment/processes/<token UUID>.json`, guarded by
/// `processes/recovery.lock`. Process recovery reads the same files after a crash.
struct WebProcessRecords: Sendable {
    let environment: EnvironmentLayout
    let gate: StartGate
    let recorder: ActiveRunRecorder

    /// Takes the environment lock that the engine holds for the whole run.
    func lock() throws -> InstanceLock {
        try OwnedDirectory.create(environment.processesDirectory)
        return try InstanceLock.acquire(at: environment.recoveryLockFile, messages: WebEnvironmentLock.messages)
    }

    /// Deletes stale records of earlier runs and refuses a start while a recorded process may live.
    func clearPrevious(holding lock: InstanceLock) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: environment.processesDirectory.path)
        for name in names.sorted() where name.hasSuffix(".json") {
            guard let id = UUID(uuidString: String(name.dropLast(5))) else { continue }
            _ = try gate.requireStopped(environment.processRecord(id), holding: lock)
        }
    }

    /// Saves the record of a started process.
    func record(_ token: ProcessToken, pid: pid_t, label: String, signal: Int32, holding lock: InstanceLock) throws {
        let clearance = try gate.requireStopped(environment.processRecord(token.id), holding: lock)
        try recorder.record(processID: pid, runtimeID: label, gracefulSignal: signal, clearance: clearance)
    }

    /// Deletes the record of a stopped process. A record whose process may still live stays for
    /// recovery, which is the safe direction; the reason is returned.
    func remove(_ token: ProcessToken, holding lock: InstanceLock) -> String? {
        let location = environment.processRecord(token.id)
        guard FileProbe.presence(at: location.recordFile).mayExist else { return nil }
        do {
            _ = try gate.requireStopped(location, holding: lock)
            return nil
        } catch {
            return FailureDetail.describe(error)
        }
    }
}
