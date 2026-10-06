import JerdProcess
import JerdServiceKit

/// Process recovery and retained runtime backups. JerdLive implements it with
/// `ProcessRecoveryService` and `BackupRetentionService`.
public protocol RecoveryPort: Sendable {
    /// The saved run records of a previous session, classified.
    func inspectProcesses() async -> [RecoveryFinding]
    /// Clears a stale record, or requests a graceful stop of a verified process.
    func recoverProcess(_ id: String) async throws
    /// The runtime update backups of mail and storage.
    func inspectBackups() async -> [RetainedBackup]
    /// Deletes one backup that is not protected.
    func removeBackup(_ id: String) async throws
}
