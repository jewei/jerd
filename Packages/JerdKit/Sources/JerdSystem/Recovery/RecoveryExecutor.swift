import Foundation
import JerdFoundation

/// Runs one approved recovery. It has no compensation: each step is journaled, and a failure keeps
/// the journal for a later, newly approved attempt.
///
/// Before any change it keeps a copy of the journal in `recovery.previous.json`. A later attempt at
/// the same transaction never replaces that first copy (fixed problem 2). A restore writes back the
/// exact bytes of the earlier registration.
struct RecoveryExecutor {
    let directory: RootRecordDirectory
    let hosts: any HostsFileAccessing
    let trust: any CertificateTrustChanging

    func run(_ action: SystemRecoveryAction, pending: PendingRecord, current: Data, after: Data) async throws {
        try keepFirstCopy(of: pending)
        var journal = pending.journal
        try save(&journal, phase: "Approved recovery started; inspect current state before retrying")
        try await hosts.replace(expected: current, with: after)
        try save(&journal, phase: "Recovery host entries were written; certificate change is pending")
        if action == .restorePrevious, let target = pending.previous {
            try await trust.install(target.trust(), replacingOwned: true)
            try save(&journal, phase: "Recovery certificate trust was written")
            let bytes = try pending.journal?.previousBytes ?? HelperRecordCodec.encode(target)
            try directory.write(bytes, to: .registration)
        } else {
            try await trust.remove(pending.reference.trust().certificate)
            try save(&journal, phase: "Recovery certificate was removed")
            try directory.remove(.registration)
        }
        try directory.remove(.pending)
    }

    /// Writes the copy unless it already holds this transaction from an earlier attempt.
    func keepFirstCopy(of pending: PendingRecord) throws {
        if let existing = try directory.read(.recoveryCopy), isSameTransaction(existing, pending) { return }
        try directory.write(pending.bytes, to: .recoveryCopy)
    }

    private func isSameTransaction(_ copy: Data, _ pending: PendingRecord) -> Bool {
        if copy == pending.bytes { return true }
        guard let journal = pending.journal,
            case .journal(let earlier) = try? HelperRecordCodec.decodePending(copy)
        else { return false }
        return earlier.isSameTransaction(as: journal)
    }

    private func save(_ journal: inout SetupJournal?, phase: String) throws {
        guard var current = journal else { return }
        current.phase = phase
        try directory.write(HelperRecordCodec.encode(current), to: .pending)
        journal = current
    }
}
