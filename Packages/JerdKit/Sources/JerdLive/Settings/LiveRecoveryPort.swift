import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdUI

/// The `RecoveryPort` of Advanced: saved process records and the runtime update backups of
/// mail and storage. Both services read only the fixed locations of the data layout.
package struct LiveRecoveryPort: RecoveryPort {
    let processes: ProcessRecoveryService
    let backups: BackupRetentionService

    package init(processes: ProcessRecoveryService, backups: BackupRetentionService) {
        self.processes = processes
        self.backups = backups
    }

    package init(layout: DataLayout) {
        self.init(processes: ProcessRecoveryService(layout: layout), backups: BackupRetentionService(layout: layout))
    }

    package func inspectProcesses() async -> [RecoveryFinding] {
        await processes.inspect()
    }

    /// Clears a stale record, or stops a verified orphan gracefully. It never sends `SIGKILL`.
    package func recoverProcess(_ id: String) async throws {
        try await processes.recover(id)
    }

    package func inspectBackups() async -> [RetainedBackup] {
        await backups.inspect()
    }

    package func removeBackup(_ id: String) async throws {
        try await backups.remove(id)
    }
}
