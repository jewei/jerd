import Foundation
import JerdFoundation
import JerdProcess

extension ManagedInstance {
    /// Stops a running server while keeping the lock (or takes the lock), clears the run record
    /// under the lock, and returns a lease. Every other operation is refused until `endMaintenance`.
    ///
    /// - Throws: `.unavailable(busy)` during another operation, the stop error (the state is then
    ///   `stuck`), or a lock or run-record error.
    public func beginMaintenance() async throws -> MaintenanceLease {
        try requireNoLease()
        guard !state.isBusy else { throw JerdError.unavailable(messages.busy) }
        let id = UUID()
        lease = id
        do {
            let wasRunning = process != nil
            if let owned = process {
                apply(.stopRequested(pid: owned.processID))
                let result = await stopOwned(owned, keepLock: true, intent: .user)
                if let message = result.failureMessage { throw JerdError.processFailed(message) }
            }
            let profile = definition.profile
            try OwnedDirectory.create(profile.folder, within: profile.containingDirectory)
            let held = try lock ?? InstanceLock.acquire(at: profile.record.lockFile, messages: profile.messages.lock)
            lock = held
            _ = try effects.startGate.requireStopped(profile.record, holding: held)
            return MaintenanceLease(id: id, wasRunning: wasRunning, lock: held)
        } catch {
            lease = nil
            releaseLockIfIdle()
            throw error
        }
    }

    /// Starts the server inside the lease with `definition`. A failure keeps the lock.
    public func start(in lease: MaintenanceLease, with definition: any ServiceDefinition) async throws {
        try requireLease(lease)
        guard process == nil else { throw JerdError.unavailable(messages.alreadyHasProcess) }
        self.definition = definition
        apply(.startRequested)
        try await performStart(keepLockOnFailure: true)
    }

    /// Stops the server inside the lease and keeps the lock. Without a process it does nothing.
    public func stop(in lease: MaintenanceLease) async throws {
        try requireLease(lease)
        guard let owned = process else { return }
        apply(.stopRequested(pid: owned.processID))
        let result = await stopOwned(owned, keepLock: true, intent: .user)
        if let message = result.failureMessage { throw JerdError.processFailed(message) }
    }

    /// Replaces the definition inside the lease, for example after a restore of old settings.
    public func replaceDefinition(_ next: any ServiceDefinition, in lease: MaintenanceLease) throws {
        try requireLease(lease)
        guard process == nil else { throw JerdError.unavailable(messages.alreadyHasProcess) }
        definition = next
    }

    /// Ends the lease. The lock stays only while a process is owned. With `failure`, a stopped
    /// instance shows that failure.
    public func endMaintenance(_ lease: MaintenanceLease, failure: String? = nil) {
        guard self.lease == lease.id else { return }
        self.lease = nil
        if let failure, process == nil { apply(.operationFailed(reason: failure)) }
        releaseLockIfIdle()
    }

    func requireLease(_ lease: MaintenanceLease) throws {
        guard self.lease == lease.id, lease.lock.isHeld, lock === lease.lock else {
            throw JerdError.unavailable(ServiceMessages.staleLease)
        }
    }
}
