import Darwin
import Foundation
import JerdFoundation

extension SetupStore {
    /// Applies the approved hostnames and CA for `ownerUID`: hosts section, then trust, then registration.
    ///
    /// A changed host set keeps the same CA. A different CA needs a removal first. A recorded section
    /// that is already gone is written again.
    public func configure(
        _ request: SystemRegistrationRequest, ownerUID: uid_t, trust: any CertificateTrustChanging
    )
        async throws
    {
        try beginOperation(SetupOperation.configure.rawValue)
        defer { endOperation() }
        try OwnerPolicy.require(ownerUID)
        let next = RegistrationRecord(
            ownerUID: ownerUID, installationID: request.installationID,
            hostnames: try ValidatedHostnames(request.hostnames), certificateDER: request.certificateDER,
            trustPolicy: request.trustPolicy)
        let intended = try next.trust()
        let previous = try committedRecord(ownerUID: ownerUID)
        if let previous, !previous.record.hasSameCertificate(as: next) {
            throw JerdError.invalid("Remove the previous Jerd system setup before replacing its CA.")
        }
        let before = try hosts.read()
        let after = try HostsSection.replacing(
            in: before, with: next.hostnames.values, recorded: previous?.record.hostnames.values ?? [])
        let plan = SetupPlan(directory: directory, hosts: hosts, trust: trust, before: before, after: after)
        let steps = [
            plan.hostsStep(donePhase: "Host entries were written"),
            plan.installStep(intended, previous: try previous?.record.trust()),
            plan.writeRegistrationStep(try HelperRecordCodec.encode(next), previousBytes: previous?.bytes),
        ]
        try await run(
            .configure, steps: steps, previous: previous, intended: next, before: before, failureTitle: "Setup failed")
    }

    /// Removes the setup of `ownerUID`: hosts section, then trust and CA, then registration.
    /// Without a setup, it does nothing. A hosts section that is already gone is not an error.
    public func remove(ownerUID: uid_t, trust: any CertificateTrustChanging) async throws {
        try beginOperation(SetupOperation.remove.rawValue)
        defer { endOperation() }
        try OwnerPolicy.require(ownerUID)
        guard let committed = try committedRecord(ownerUID: ownerUID) else { return }
        let recorded = try committed.record.trust()
        let before = try hosts.read()
        let after = try HostsSection.replacing(in: before, with: [], recorded: committed.record.hostnames.values)
        let plan = SetupPlan(directory: directory, hosts: hosts, trust: trust, before: before, after: after)
        // A section that another tool already deleted needs no hosts write.
        let hostsSteps = after == before ? [] : [plan.hostsStep(donePhase: "Host entries were removed")]
        let steps =
            hostsSteps + [
                plan.removeTrustStep(recorded),
                plan.removeRegistrationStep(previousBytes: committed.bytes),
            ]
        try await run(
            .remove, steps: steps, previous: committed, intended: nil, before: before, failureTitle: "Removal failed")
    }

    /// Saves the hosts backup, runs the journaled steps, and deletes the backup after success.
    private func run(
        _ operation: SetupOperation, steps: [SetupStep], previous: (record: RegistrationRecord, bytes: Data)?,
        intended: RegistrationRecord?, before: Data, failureTitle: String
    ) async throws {
        try directory.write(before, to: .hostsBackup)
        let journal = SetupJournal(
            operation: operation, previous: previous?.record, previousBytes: previous?.bytes, intended: intended,
            hostsSHA256: CertificateIdentity.sha256Hex(before), phase: "Prepared; system writes have not started")
        var transaction = SetupTransaction(
            directory: directory, journal: journal, steps: steps, failureTitle: failureTitle)
        try await transaction.run()
        // The backup is evidence for an unfinished transaction only. A stale copy is harmless,
        // so a failed deletion does not fail the finished transaction.
        try? directory.remove(.hostsBackup)
    }
}
