import Darwin
import Foundation
import JerdFoundation
import JerdServiceKit

extension StorageManager {
    /// Recovers an unfinished runtime update, then starts RustFS. Errors keep the kind of the
    /// failed step.
    public func start() async throws {
        try await coordinator.start()
    }

    /// Stops RustFS gracefully, also while a runtime update needs recovery. Every bucket and
    /// object stays. A stop that exit detection began is joined. The end of the launch clears the
    /// listed names and invalidates its S3 session.
    public func stop() async throws {
        try await coordinator.stop()
    }

    /// The saved credentials, for the Laravel settings and the copy buttons. It reads only.
    public func credentials() async throws -> StorageCredentials {
        try await coordinator.requireLoaded()
        return try StorageData(layout: layout).credentials()
    }

    /// The PID of the running service after its listener check.
    ///
    /// - Parameter startingIfNeeded: starts a service without a process first (Save does this).
    /// - Throws: `startBeforeBuckets` unless the service runs, or the start or listener error.
    func runningService(
        startingIfNeeded: Bool, in coordinator: isolated Coordinator
    ) async throws
        -> pid_t
    {
        let instance = try coordinator.requireInstance()
        if startingIfNeeded, await instance.processID == nil { try await instance.start() }
        guard case .running(let pid) = await instance.refresh() else { throw StorageMessages.startBeforeBuckets }
        try await effects.ports.verifyOwnership(pid: pid, expected: Set(coordinator.settings.ports.ordered))
        return pid
    }

    /// A signed client of the current launch with the saved credentials, and the launch ID.
    func client(in coordinator: isolated Coordinator) throws -> (client: S3Client, launch: UUID) {
        guard let current = launch.current else { throw StorageMessages.startBeforeBuckets }
        let credentials = try StorageData(layout: layout).credentials()
        let client = S3Client(
            port: coordinator.settings.apiPort, credentials: credentials, sender: current.sender, now: now)
        return (client, current.id)
    }
}
