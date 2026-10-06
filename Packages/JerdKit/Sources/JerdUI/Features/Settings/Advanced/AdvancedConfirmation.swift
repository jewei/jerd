import JerdProcess
import JerdServiceKit
import JerdSystem
import JerdWeb

/// A step on the Advanced page that changes data or the system, and its confirmation text.
/// Every button that ends with "…" opens one of these first.
public enum AdvancedConfirmation: Equatable, Sendable {
    case recoverProcess(RecoveryFinding)
    case clearStaleRecord(RecoveryFinding)
    case deleteBackup(RetainedBackup)
    case removePHP(DevelopmentRuntime)
    case restoreHTTPS(SystemRecoveryStatus)
    case removeHTTPS(SystemRecoveryStatus)

    /// The confirmation for the action of a finding: clear for a stale record, else recover.
    public static func forFinding(_ finding: RecoveryFinding) -> AdvancedConfirmation {
        finding.state == .stale ? .clearStaleRecord(finding) : .recoverProcess(finding)
    }

    public var title: String {
        switch self {
        case .recoverProcess: "Recover this saved service?"
        case .clearStaleRecord: "Clear this stale record?"
        case .deleteBackup: "Delete this retained backup?"
        case .removePHP: "Remove this PHP runtime registration?"
        case .restoreHTTPS: "Restore the previous HTTPS setup?"
        case .removeHTTPS: "Remove the tracked HTTPS setup?"
        }
    }

    public var message: String {
        switch self {
        case .recoverProcess(let finding):
            "\(finding.detail) Jerd requests a graceful stop and waits up to 30 seconds."
        case .clearStaleRecord(let finding):
            "\(finding.detail) The saved processes are gone. Jerd removes only the record."
        case .deleteBackup:
            "This removes only the selected backup. It cannot be undone. Current service data stays in place."
        case .removePHP:
            "Jerd will remove this registration only. The runtime files stay on disk."
        case .restoreHTTPS:
            "Jerd will put back the host entries, certificate trust, and helper record from before the interrupted setup. macOS can ask for administrator approval."
        case .removeHTTPS:
            "Jerd will remove its tracked host entries, its CA certificate, and its helper record. Site records and project files will remain. macOS can ask for administrator approval."
        }
    }

    /// The title of the confirm button.
    public var confirmTitle: String {
        switch self {
        case .recoverProcess: "Recover Service"
        case .clearStaleRecord: "Clear Stale Record"
        case .deleteBackup: "Delete Backup"
        case .removePHP: "Remove Registration"
        case .restoreHTTPS: "Restore Previous Setup"
        case .removeHTTPS: "Remove Tracked Setup"
        }
    }

    /// Destructive steps use the destructive role and never confirm with Return.
    public var isDestructive: Bool {
        switch self {
        case .deleteBackup, .removePHP, .removeHTTPS: true
        case .recoverProcess, .clearStaleRecord, .restoreHTTPS: false
        }
    }

    /// The banner message while the step runs.
    public var workingMessage: String {
        switch self {
        case .recoverProcess: "Waiting for the saved service to stop safely…"
        case .clearStaleRecord: "Clearing the stale record…"
        case .deleteBackup: "Removing the selected backup…"
        case .removePHP: "Removing the PHP runtime registration…"
        case .restoreHTTPS, .removeHTTPS: "Recovering HTTPS setup. Complete or cancel the macOS approval prompt…"
        }
    }
}
