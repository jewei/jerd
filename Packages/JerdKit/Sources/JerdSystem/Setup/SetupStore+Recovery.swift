import Darwin
import Foundation
import JerdFoundation

extension SetupStore {
    /// Runs an approved recovery of the interrupted transaction of `ownerUID`.
    ///
    /// The approval must name the current record ID, and the action must be allowed now.
    public func recover(
        _ approval: SystemRecoveryApproval, ownerUID: uid_t, trust: any CertificateTrustChanging
    )
        async throws
    {
        try beginOperation("Recover HTTPS setup")
        defer { endOperation() }
        try OwnerPolicy.require(ownerUID)
        let pending = try loadPending(ownerUID: ownerUID).mapError(\.error).get()
        let assessment = try assess(pending, ownerUID: ownerUID)
        guard approval.recordID == assessment.status.id else {
            throw JerdError.unavailable("The recovery record changed. Inspect it and approve recovery again.")
        }
        guard let after = assessment.hosts(for: approval.action) else {
            throw JerdError.unavailable(
                "The recorded system state needs manual inspection. No recovery change was made.")
        }
        let executor = RecoveryExecutor(directory: directory, hosts: hosts, trust: trust)
        try await executor.run(approval.action, pending: pending, current: assessment.currentHosts, after: after)
    }

    /// Reads and validates `pending.json`. Every failure becomes an unreadable report that names the file.
    func loadPending(ownerUID: uid_t) -> Result<PendingRecord, UnreadablePending> {
        let location = directory.location(of: .pending)
        var bytes: Data?
        do {
            bytes = try directory.read(.pending)
            guard let bytes else { throw JerdError.corrupt("The helper recovery record disappeared during the check.") }
            let form = try HelperRecordCodec.decodePending(bytes)
            return .success(
                try PendingRecord.validate(form, bytes: bytes, owner: ownerUID) {
                    try self.committedRecord(ownerUID: ownerUID, allowPending: true)?.record
                })
        } catch {
            let jerd = error as? JerdError ?? .corrupt(HelperRecordCodec.describe(error))
            let id = bytes.map(CertificateIdentity.sha256Hex) ?? "unreadable"
            let report = RecoveryAssessor.unreadable(id: id, reason: jerd.message, location: location)
            return .failure(UnreadablePending(error: jerd, report: report))
        }
    }

    /// Gathers the evidence of `pending` now and assesses it.
    func assess(_ pending: PendingRecord, ownerUID: uid_t) throws -> AssessedRecovery {
        let current = try hosts.read()
        let committed: Result<RegistrationRecord?, RecoveryReadFailure>
        do {
            committed = .success(try committedRecord(ownerUID: ownerUID, allowPending: true)?.record)
        } catch {
            committed = .failure(RecoveryReadFailure(message: HelperRecordCodec.describe(error)))
        }
        let backup: Result<String?, RecoveryReadFailure>
        do {
            backup = .success(try directory.read(.hostsBackup).map(CertificateIdentity.sha256Hex))
        } catch {
            backup = .failure(RecoveryReadFailure(message: HelperRecordCodec.describe(error)))
        }
        let evidence = RecoveryEvidence(
            pending: pending, hosts: current, committed: committed, backupDigest: backup,
            trustPresent: isTrustPresent(pending.reference))
        return AssessedRecovery(assessment: RecoveryAssessor.assess(evidence), currentHosts: current)
    }

    /// A trust check that cannot run counts as "not confirmed", which only changes a detail line.
    private func isTrustPresent(_ record: RegistrationRecord) -> Bool {
        do {
            return try inspector.isInstalled(record.trust())
        } catch {
            return false
        }
    }
}
