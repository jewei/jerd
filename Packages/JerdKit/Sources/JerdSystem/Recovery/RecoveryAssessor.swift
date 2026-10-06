import Foundation
import JerdFoundation

/// Pure policy: from the evidence of an interrupted transaction, decide which recoveries are safe
/// and explain the state to the user.
///
/// Restore needs a journal, a known registration, and a hosts section that matches a recorded
/// state and can be changed back. Remove needs a known registration and a matching hosts section.
/// The hosts backup is reported, but it does not gate a restore, because a restore never uses it.
enum RecoveryAssessor {
    /// The result: the report for the user and the hosts bytes of each allowed action.
    struct Assessment: Sendable {
        let status: SystemRecoveryStatus
        /// The hosts bytes after a restore, or nil when a restore is not allowed.
        let restoredHosts: Data?
        /// The hosts bytes after a removal, or nil when a removal is not allowed.
        let removedHosts: Data?

        func hosts(for action: SystemRecoveryAction) -> Data? {
            action == .restorePrevious ? restoredHosts : removedHosts
        }
    }

    static func assess(_ evidence: RecoveryEvidence) -> Assessment {
        let pending = evidence.pending
        var details: [String] = []
        let recordKnown = registrationDetails(evidence, into: &details)
        backupDetails(evidence, into: &details)
        let removal = hosts(evidence.hosts, pending: pending, target: [])
        let restore = hosts(evidence.hosts, pending: pending, target: pending.previous?.hostnames.values ?? [])
        details.append(
            removal != nil
                ? "The current Jerd host section matches a recorded state. Unrelated host entries will be retained."
                : "The Jerd host section changed outside this transaction. Inspect the host file manually.")
        details.append(
            evidence.trustPresent
                ? "The recorded certificate trust is currently present."
                : "The recorded certificate trust is absent or could not be confirmed.")
        details.append(
            "Recovery changes only the recorded Jerd host section, certificate, and registration. "
                + "The operation can request macOS approval.")
        let canRestore = pending.journal != nil && recordKnown && restore != nil
        let canRemove = recordKnown && removal != nil
        let status = SystemRecoveryStatus(
            id: pending.id, operation: pending.journal?.operation ?? "Interrupted legacy HTTPS setup",
            phase: pending.journal?.phase ?? "Unknown", details: details, canRestore: canRestore, canRemove: canRemove,
            installationID: pending.reference.installationID, certificateDER: pending.reference.certificateDER,
            previousHostnames: pending.previous?.hostnames.strings ?? [],
            intendedHostnames: pending.intended?.hostnames.strings ?? [], policies: policies(pending))
        return Assessment(
            status: status, restoredHosts: canRestore ? restore : nil, removedHosts: canRemove ? removal : nil)
    }

    /// The report of a `pending.json` that cannot be read or validated. No action is allowed.
    static func unreadable(id: String, reason: String, location: URL) -> SystemRecoveryStatus {
        SystemRecoveryStatus(
            id: id, operation: "Unreadable HTTPS setup record", phase: "Unknown",
            details: [
                reason,
                "Jerd cannot recover this record automatically. An administrator must inspect \(location.path). "
                    + "It was preserved.",
            ],
            canRestore: false, canRemove: false, installationID: nil, certificateDER: nil, previousHostnames: [],
            intendedHostnames: [], policies: [])
    }

    /// The policies that a recovery can apply, in one stable order (fixed problem 16).
    static func policies(_ pending: PendingRecord) -> [CertificateTrustPolicy] {
        Set([pending.reference.trustPolicy] + [pending.previous?.trustPolicy].compactMap { $0 }).sorted()
    }

    /// The hosts bytes with the Jerd section set to `target`, starting from the first recorded state
    /// (previous, intended, none) that the current section matches. Nil when no state matches.
    ///
    /// The match uses the section rule only. The external-mapping rule applies to the `target`
    /// hostnames alone, so an outside line that maps a recorded name blocks no removal (fixed review L1).
    static func hosts(_ current: Data, pending: PendingRecord, target: [Hostname]) -> Data? {
        let recorded = [pending.previous?.hostnames.values ?? [], pending.intended?.hostnames.values ?? [], []]
        guard let expected = recorded.first(where: { HostsSection.tracks($0, in: current) }) else { return nil }
        do {
            return try HostsSection.replacing(in: current, with: target, expecting: expected)
        } catch {
            return nil  // For example, a target hostname got an external mapping after the crash.
        }
    }

    private static func registrationDetails(_ evidence: RecoveryEvidence, into details: inout [String]) -> Bool {
        switch evidence.committed {
        case .failure(let failure):
            details.append(failure.message)
            return false
        case .success(let record?) where record != evidence.pending.previous && record != evidence.pending.intended:
            details.append("The saved registration differs from this transaction. Inspect it manually.")
            return false
        case .success:
            return true
        }
    }

    private static func backupDetails(_ evidence: RecoveryEvidence, into details: inout [String]) {
        guard let journal = evidence.pending.journal else {
            details.append(
                "This legacy record does not identify the interrupted operation. "
                    + "You can remove the recorded setup after approval, then enable HTTPS again.")
            return
        }
        if case .failure(let failure) = evidence.backupDigest { details.append(failure.message) }
        let matches = (try? evidence.backupDigest.get()) == journal.hostsSHA256
        details.append(
            matches
                ? "The original host-file backup is present and matches its record."
                : "The original host-file backup is missing or changed. Recovery uses only the current Jerd host section."
        )
    }
}
