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
        for location in try savedLocations() { _ = try gate.requireStopped(location, holding: lock) }
    }

    /// Refuses while a recorded process of an earlier run may live. It needs no lock and changes
    /// no file, so the coordinator runs it before its port checks: an orphaned Caddy still holds
    /// 80 and 443 after a crash.
    func requireNoLivePrevious() throws {
        guard FileProbe.presence(at: environment.processesDirectory).mayExist else { return }
        for location in try savedLocations() { try gate.requireNoLiveRecord(location) }
    }

    /// The record locations in `processes/`, in name order. Other files are ignored.
    private func savedLocations() throws -> [RecordLocation] {
        let names = try FileManager.default.contentsOfDirectory(atPath: environment.processesDirectory.path)
        return names.sorted().compactMap { name in
            guard name.hasSuffix(".json"), let id = UUID(uuidString: String(name.dropLast(5))) else { return nil }
            return environment.processRecord(id)
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
