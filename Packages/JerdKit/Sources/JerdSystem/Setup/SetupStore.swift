import Darwin
import Foundation
import JerdFoundation

/// The helper's setup of one machine: a registration, the tracked hosts section, and the CA trust.
///
/// One configure, remove, or recover runs at a time. `status` can run during a transaction (the
/// actor suspends while macOS asks for approval); it then reports the operation as in progress,
/// never as interrupted. The helper supplies the fixed folder and hosts file; nothing comes from XPC.
public actor SetupStore {
    let directory: RootRecordDirectory
    let hosts: any HostsFileAccessing
    let inspector: any CertificateTrustInspecting
    private var activeOperation: String?

    public init(directory: RootRecordDirectory, hosts: any HostsFileAccessing, trust: any CertificateTrustInspecting) {
        self.directory = directory
        self.hosts = hosts
        self.inspector = trust
    }

    /// The setup of `ownerUID`. An unreadable recovery record gives a report, not an error.
    public func status(ownerUID: uid_t) throws -> SystemSetupStatus {
        if let activeOperation { return SystemSetupStatus(operationInProgress: activeOperation) }
        if directory.exists(.pending) { return try pendingStatus(ownerUID: ownerUID) }
        guard let record = try committedRecord(ownerUID: ownerUID)?.record else { return .empty }
        let trust = try record.trust()
        return SystemSetupStatus(
            hostnames: record.hostnames.strings, installationID: record.installationID,
            certificateSHA256: trust.certificate.sha256, certificateDER: record.certificateDER,
            hostsConfigured: HostsSection.maps(record.hostnames.values, in: try hosts.read()),
            trustConfigured: try inspector.isInstalled(trust), trustPolicy: record.trustPolicy)
    }

    /// Marks the start of a transaction. A second transaction is refused.
    func beginOperation(_ name: String) throws {
        guard activeOperation == nil else {
            throw JerdError.unavailable("Wait for the current system operation to finish.")
        }
        activeOperation = name
    }

    func endOperation() { activeOperation = nil }

    /// The registration of `ownerUID` and its exact bytes, or nil when there is none.
    ///
    /// - Parameter allowPending: read even while a journal exists (only for recovery evidence).
    func committedRecord(
        ownerUID: uid_t, allowPending: Bool = false
    ) throws -> (record: RegistrationRecord, bytes: Data)? {
        guard allowPending || !directory.exists(.pending) else {
            throw JerdError.unavailable(
                "A previous system setup was interrupted. A recovery record is retained in the helper directory. "
                    + "Do not overwrite it.")
        }
        guard let bytes = try directory.read(.registration) else { return nil }
        let record = try HelperRecordCodec.decodeRegistration(bytes)
        guard record.ownerUID == ownerUID else {
            throw JerdError.unavailable("The system setup belongs to another user.")
        }
        return (record, bytes)
    }

    private func pendingStatus(ownerUID: uid_t) throws -> SystemSetupStatus {
        let report: SystemRecoveryStatus
        var reference: RegistrationRecord?
        switch loadPending(ownerUID: ownerUID) {
        case .success(let pending):
            report = try assess(pending, ownerUID: ownerUID).status
            reference = pending.reference
        case .failure(let unreadable):
            report = unreadable.report
        }
        return SystemSetupStatus(
            hostnames: reference?.hostnames.strings ?? [], installationID: reference?.installationID,
            certificateSHA256: reference.map { CertificateIdentity.sha256Hex($0.certificateDER) },
            certificateDER: reference?.certificateDER, trustPolicy: reference?.trustPolicy ?? .hostnames,
            recovery: report)
    }
}
