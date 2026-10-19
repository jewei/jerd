import Darwin
import Foundation
import JerdFoundation

extension SetupStore {
    /// Replaces the CA of the setup of `ownerUID` with Jerd's CA that may sign only `.test` names:
    /// first the new trust, then the removal of the old CA, then the registration. The hosts stay.
    /// A failure puts the old trust back and removes the new CA, so the old CA keeps working.
    public func replaceCA(
        _ request: SystemRegistrationRequest, ownerUID: uid_t, trust: any CertificateTrustChanging
    )
        async throws
    {
        try beginOperation(SetupOperation.replaceCA.rawValue)
        defer { endOperation() }
        try OwnerPolicy.require(ownerUID)
        guard let previous = try committedRecord(ownerUID: ownerUID) else {
            throw JerdError.invalid("There is no Jerd system setup whose CA can be replaced.")
        }
        let next = RegistrationRecord(
            ownerUID: ownerUID, installationID: request.installationID,
            hostnames: try ValidatedHostnames(request.hostnames), certificateDER: request.certificateDER,
            trustPolicy: request.trustPolicy)
        try CAReplacementRule.require(next, replacing: previous.record)
        let before = try hosts.read()
        let plan = SetupPlan(directory: directory, hosts: hosts, trust: trust, before: before, after: before)
        let steps = [
            plan.installStep(try next.trust(), previous: nil),
            plan.removeTrustStep(try previous.record.trust()),
            plan.writeRegistrationStep(try HelperRecordCodec.encode(next), previousBytes: previous.bytes),
        ]
        try await run(
            .replaceCA, steps: steps, previous: previous, intended: next, before: before,
            failureTitle: "CA replacement failed")
    }
}
