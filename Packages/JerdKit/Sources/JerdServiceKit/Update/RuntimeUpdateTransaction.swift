import Foundation
import JerdFoundation

/// Replaces the runtime of a single-instance service (Mail, Storage) as a journaled transaction.
///
/// Order: lease (stop, keep the lock) → validate the old data → back up every named item and
/// write the journal → apply the new runtime → start and verify → stop again if the service was
/// stopped → delete the journal. Any failure stops the server, moves the changed items to
/// `failed-attempt-<UUID>/`, restores the backup, and restarts the old runtime when it ran.
/// The lock is held from the first step to the last, also during the restore. Backups stay until
/// the user deletes them in Advanced.
public struct RuntimeUpdateTransaction: Sendable {
    /// The service words in update messages.
    public struct Messages: Sendable {
        /// "Mail" or "Storage".
        public var service: String
        /// For example "The previous runtime and inbox were restored."
        public var restored: String
        /// For example "Stop mail before recovering its runtime update."
        public var stopBeforeRecovery: String

        public init(service: String, restored: String, stopBeforeRecovery: String) {
            self.service = service
            self.restored = restored
            self.stopBeforeRecovery = stopBeforeRecovery
        }
    }

    static let pendingMessage = "Recover the previous runtime update before starting another update."
    static let invalidJournalMessage = "The runtime update record is invalid. Backup files were preserved."
    static let tooLargeMessage = "The runtime update record is too large."
    static let invalidBackupMessage = "A runtime backup directory is invalid."

    /// The service folder that contains every named item.
    public let root: URL
    /// `runtime-update.json`.
    public let journalFile: URL
    /// `runtime-backups/`.
    public let backupsDirectory: URL
    /// The service lock. Every step requires a lease on it.
    public let lockFile: URL
    /// The items that a new journal covers, for example `["settings.json", "inbox"]`.
    public let names: [String]
    public let messages: Messages

    public init(
        root: URL, journalFile: URL, backupsDirectory: URL, lockFile: URL, names: [String], messages: Messages
    ) {
        self.root = root
        self.journalFile = journalFile
        self.backupsDirectory = backupsDirectory
        self.lockFile = lockFile
        self.names = names
        self.messages = messages
    }

    /// True while a journal exists, or its presence cannot be ruled out.
    public var isPending: Bool { FileProbe.presence(at: journalFile).mayExist }

    /// Runs the whole update on `instance` and switches it to `updated`.
    ///
    /// A pending journal refuses the update before the server stops, and again inside the lease,
    /// because a journal can appear while the lease waits for the stop.
    /// - Throws: `.unavailable(pending)` while a journal exists, or `.processFailed` with "update
    ///   failed" and whether the old state was restored.
    public func run(
        on instance: ManagedInstance, to updated: any ServiceDefinition, steps: RuntimeUpdateSteps
    ) async throws {
        guard !isPending else { throw JerdError.unavailable(Self.pendingMessage) }
        let lease = try await instance.beginMaintenance()
        var backedUp = false
        do {
            guard !isPending else { throw JerdError.unavailable(Self.pendingMessage) }
            try await steps.validatePrevious()
            _ = try await beginBackup(holding: lease)
            backedUp = true
            try await steps.apply()
            try await instance.start(in: lease, with: updated)
            try await steps.verifyStarted()
            if !lease.wasRunning { try await instance.stop(in: lease) }
            try commit(holding: lease)
        } catch {
            throw await rollBack(after: error, backedUp: backedUp, on: instance, lease: lease, steps: steps)
        }
        await instance.endMaintenance(lease)
    }

    func requireLease(_ lease: MaintenanceLease) throws {
        guard lease.guards(lockFile) else { throw JerdError.unavailable(ServiceMessages.staleLease) }
    }
}
