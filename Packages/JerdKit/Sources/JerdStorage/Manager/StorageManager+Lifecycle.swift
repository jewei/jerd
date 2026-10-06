import Darwin
import JerdFoundation
import JerdServiceKit

extension StorageManager {
    /// Recovers an unfinished runtime update, then starts RustFS. Errors keep the kind of the
    /// failed step.
    public func start() async throws {
        try await exclusive(allowingRecovery: true) {
            guard let instance, settings.runtime != nil else { throw StorageMessages.runtimeMissing }
            try await recoverPendingUpdate()
            try await startService(instance)
        }
    }

    /// Stops RustFS gracefully, also while a runtime update needs recovery. Every bucket and
    /// object stays. A stop that exit detection began is joined.
    public func stop() async throws {
        try await exclusive(allowingRecovery: true) {
            defer { listed.clear() }
            try await instance?.stop()
        }
    }

    /// The saved credentials, for the Laravel settings and the copy buttons. It reads only.
    public func credentials() throws -> StorageCredentials {
        guard loaded else { throw StorageMessages.notLoaded }
        return try StorageData(layout: layout).credentials()
    }

    /// Starts `instance` with a cleared bucket list. The readiness probe fills the list.
    func startService(_ instance: ManagedInstance) async throws {
        listed.clear()
        try await instance.start()
    }

    /// The PID of the running service after its listener check.
    ///
    /// - Parameter startingIfNeeded: starts a service without a process first (Save does this).
    /// - Throws: `startBeforeBuckets` unless the service runs, or the start or listener error.
    func runningService(startingIfNeeded: Bool) async throws -> pid_t {
        guard let instance, settings.runtime != nil else { throw StorageMessages.runtimeMissing }
        if startingIfNeeded, await instance.processID == nil { try await startService(instance) }
        guard case .running(let pid) = await instance.refresh() else { throw StorageMessages.startBeforeBuckets }
        try await effects.ports.verifyOwnership(pid: pid, expected: Set(settings.ports.ordered))
        return pid
    }

    /// A signed client of the running service with the saved credentials.
    func client() throws -> S3Client {
        S3Client(
            port: settings.apiPort, credentials: try StorageData(layout: layout).credentials(), sender: sender, now: now
        )
    }
}
