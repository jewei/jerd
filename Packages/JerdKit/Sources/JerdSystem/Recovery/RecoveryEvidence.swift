import Foundation

/// Everything that the recovery assessment reads, gathered by the setup store at one moment.
struct RecoveryEvidence: Sendable {
    let pending: PendingRecord
    /// The current hosts bytes.
    let hosts: Data
    /// The committed registration (nil when absent), or the message of the read failure.
    let committed: Result<RegistrationRecord?, RecoveryReadFailure>
    /// The SHA-256 of `hosts.previous` (nil when absent), or the message of the read failure.
    let backupDigest: Result<String?, RecoveryReadFailure>
    /// True when the recorded trust is confirmed present.
    let trustPresent: Bool
}

/// The message of a failed read, kept as evidence.
struct RecoveryReadFailure: Error, Equatable, Sendable {
    let message: String
}
