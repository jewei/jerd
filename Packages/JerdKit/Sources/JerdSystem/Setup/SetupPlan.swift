import Foundation
import JerdFoundation

/// Builds the steps of configure and remove. Each step names its journal phases, its compensation,
/// and which failures may leave its effect behind.
struct SetupPlan: Sendable {
    let directory: RootRecordDirectory
    let hosts: any HostsFileAccessing
    let trust: any CertificateTrustChanging
    let before: Data
    let after: Data

    /// Replaces the hosts section. A `.partialChange` means a racing writer's file is preserved
    /// beside the hosts file, so the journal keeps that message and nothing is undone.
    func hostsStep(donePhase: String) -> SetupStep {
        let (hosts, before, after) = (hosts, before, after)
        return SetupStep(
            label: "host entries", donePhase: donePhase,
            apply: { try await hosts.replace(expected: before, with: after) },
            undo: { try await hosts.replace(expected: after, with: before) },
            classify: { error in
                guard let error = error as? JerdError, error.kind == .partialChange else { return .init() }
                return .init(phase: "Host replacement needs recovery: \(error.message)", retainNote: error.message)
            })
    }

    /// Installs the trust. The undo puts back the previous trust, or removes the new CA.
    func installStep(_ intended: CertificateTrust, previous: CertificateTrust?) -> SetupStep {
        let trust = trust
        return SetupStep(
            label: "certificate trust", startPhase: "Certificate approval started; its result may be unknown",
            donePhase: "Certificate trust was written",
            apply: { try await trust.install(intended, replacingOwned: previous != nil) },
            undo: {
                if let previous {
                    try await trust.install(previous, replacingOwned: true)
                } else {
                    try await trust.remove(intended.certificate)
                }
            },
            classify: { error in
                switch (error as? JerdError)?.kind {
                case .partialChange: return .init(undo: true)
                case .approvalInterrupted:
                    return .init(
                        retainNote: "Certificate approval was interrupted. Its result is unknown; "
                            + "the recovery record was retained.")
                default: return .init()
                }
            })
    }

    /// Removes the trust and the CA. Any failure can leave the trust partly removed, so the
    /// recorded trust is always installed again (fixed problem 6: only after this step ran).
    func removeTrustStep(_ recorded: CertificateTrust) -> SetupStep {
        let trust = trust
        return SetupStep(
            label: "certificate trust", startPhase: "Certificate removal started; its result may be unknown",
            donePhase: "Certificate was removed",
            apply: { try await trust.remove(recorded.certificate) },
            undo: { try await trust.install(recorded, replacingOwned: true) },
            classify: { error in
                guard (error as? JerdError)?.kind == .approvalInterrupted else { return .init(undo: true) }
                return .init(
                    undo: true,
                    retainNote:
                        "Certificate approval was interrupted. Inspect the retained recovery record before retrying.")
            })
    }

    /// Writes the new registration. The undo writes back the exact earlier bytes (fixed problem 5).
    func writeRegistrationStep(_ bytes: Data, previousBytes: Data?) -> SetupStep {
        let directory = directory
        return SetupStep(
            label: "registration", donePhase: "Registration was written",
            apply: { try directory.write(bytes, to: .registration) },
            undo: {
                if let previousBytes {
                    try directory.write(previousBytes, to: .registration)
                } else {
                    try directory.remove(.registration)
                }
            })
    }

    /// Deletes the registration. The undo writes back its exact bytes.
    func removeRegistrationStep(previousBytes: Data) -> SetupStep {
        let directory = directory
        return SetupStep(
            label: "registration", donePhase: "Registration was removed",
            apply: { try directory.remove(.registration) },
            undo: { try directory.write(previousBytes, to: .registration) })
    }
}
