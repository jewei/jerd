import Foundation
import Darwin

public protocol CertificateTrustManaging: Sendable {
    func validate(_ der: Data, installationID: UUID) throws
    func isInstalled(_ der: Data, hostnames: [String], policy: CertificateTrustPolicy) throws -> Bool
    func install(_ der: Data, hostnames: [String], policy: CertificateTrustPolicy, replacingOwned: Bool) async throws
    func remove(_ der: Data) async throws
}

public extension CertificateTrustManaging {
    func isInstalled(_ der: Data, hostname: String) throws -> Bool { try isInstalled(der, hostnames: [hostname], policy: .hostnames) }
    func install(_ der: Data, hostname: String, replacingOwned: Bool) async throws {
        try await install(der, hostnames: [hostname], policy: .hostnames, replacingOwned: replacingOwned)
    }
}

/// One installation owns a set of registered hostnames. The helper supplies fixed paths.
/// All operations are serialized. Other users cannot change this user's setup.
public actor PrivilegedSetupStore {
    private struct Registration: Codable, Equatable {
        var schemaVersion = 3
        let ownerUID: uid_t
        let installationID: UUID
        let hostnames: [String]
        let certificateDER: Data
        let trustPolicy: CertificateTrustPolicy
        init(ownerUID: uid_t, installationID: UUID, hostnames: [String], certificateDER: Data, trustPolicy: CertificateTrustPolicy) {
            self.ownerUID = ownerUID; self.installationID = installationID
            self.hostnames = hostnames; self.certificateDER = certificateDER
            self.trustPolicy = trustPolicy
        }
        private enum CodingKeys: String, CodingKey { case schemaVersion, ownerUID, installationID, hostnames, hostname, certificateDER, trustPolicy }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let version = try values.decode(Int.self, forKey: .schemaVersion)
            guard (1...3).contains(version) else { throw JerdError.corruptConfiguration("The helper registration version is unsupported.") }
            ownerUID = try values.decode(uid_t.self, forKey: .ownerUID)
            installationID = try values.decode(UUID.self, forKey: .installationID)
            certificateDER = try values.decode(Data.self, forKey: .certificateDER)
            hostnames = try Hostname.validatedSet(version == 1 ? [values.decode(String.self, forKey: .hostname)] : values.decode([String].self, forKey: .hostnames))
            trustPolicy = version < 3 ? .hostnames : try values.decode(CertificateTrustPolicy.self, forKey: .trustPolicy)
        }
        func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(schemaVersion, forKey: .schemaVersion)
            try values.encode(ownerUID, forKey: .ownerUID)
            try values.encode(installationID, forKey: .installationID)
            try values.encode(hostnames, forKey: .hostnames)
            try values.encode(certificateDER, forKey: .certificateDER)
            try values.encode(trustPolicy, forKey: .trustPolicy)
        }
    }
    private struct Journal: Codable {
        var schemaVersion = 1
        let operation: String
        let previous: Registration?
        let previousBytes: Data?
        let intended: Registration?
        let hostsSHA256: String
        var phase: String
    }
    private struct Pending {
        let bytes: Data
        let journal: Journal?
        let reference: Registration
        let previous: Registration?
        let intended: Registration?
        var id: String { InstallationCertificate.fingerprint(bytes) }
    }
    private let directory: URL
    private let expectedFileOwner: uid_t
    private let hosts: AtomicHostsFile
    private let certificates: any CertificateTrustManaging
    private var recordURL: URL { directory.appendingPathComponent("registration.json") }
    private var pendingURL: URL { directory.appendingPathComponent("pending.json") }
    private var mutation = false

    public init(directory: URL, expectedFileOwner: uid_t, hosts: AtomicHostsFile,
                certificates: any CertificateTrustManaging) {
        self.directory = directory; self.expectedFileOwner = expectedFileOwner
        self.hosts = hosts; self.certificates = certificates
    }

    public func status(ownerUID: uid_t) throws -> SystemSetupStatus {
        if FileManager.default.fileExists(atPath: pendingURL.path) {
            let pending = try readPending(ownerUID)
            var result = SystemSetupStatus(hostnames: pending.reference.hostnames,
                installationID: pending.reference.installationID, certificateSHA256: InstallationCertificate.fingerprint(pending.reference.certificateDER),
                certificateDER: pending.reference.certificateDER, trustPolicy: pending.reference.trustPolicy)
            result.recovery = try recoveryStatus(pending, ownerUID: ownerUID)
            return result
        }
        guard let record = try ownedRecord(ownerUID) else { return SystemSetupStatus() }
        return SystemSetupStatus(hostnames: record.hostnames, installationID: record.installationID,
            certificateSHA256: InstallationCertificate.fingerprint(record.certificateDER),
            certificateDER: record.certificateDER,
            hostsConfigured: HostsDocument.containsRegistrations(record.hostnames, in: try hosts.read()),
            trustConfigured: try certificates.isInstalled(record.certificateDER, hostnames: record.hostnames, policy: record.trustPolicy),
            trustPolicy: record.trustPolicy)
    }

    public func configure(_ request: SystemRegistrationRequest, ownerUID: uid_t,
                          trustManager: (any CertificateTrustManaging)? = nil) async throws {
        try beginMutation(); defer { mutation = false }
        let certificates = trustManager ?? self.certificates
        guard ownerUID != 0 else { throw JerdError.invalid("Root cannot own a Jerd project environment.") }
        let hostnames = try Hostname.validatedSet(request.hostnames)
        try certificates.validate(request.certificateDER, installationID: request.installationID)
        let previous = try ownedRecord(ownerUID)
        if let previous {
            guard previous.installationID == request.installationID, previous.certificateDER == request.certificateDER else {
                throw JerdError.invalid("Remove the previous Jerd system setup before replacing its CA.")
            }
        }
        let before = try hosts.read()
        let after = try HostsDocument.replacing(before, hostnames: hostnames, expectedHostnames: previous?.hostnames ?? [])
        let next = Registration(ownerUID: ownerUID, installationID: request.installationID,
                                hostnames: hostnames, certificateDER: request.certificateDER, trustPolicy: request.trustPolicy)
        try prepareDirectory()
        // Keep a durable recovery record before crossing the hosts/trust boundary.
        try PrivateFiles.write(before, to: directory.appendingPathComponent("hosts.previous"))
        var journal = Journal(operation: "Configure HTTPS", previous: previous,
            previousBytes: previous == nil ? nil : try PrivateFiles.read(recordURL, limit: 131_072, owner: expectedFileOwner),
            intended: next, hostsSHA256: InstallationCertificate.fingerprint(before), phase: "Prepared; system writes have not started")
        try writeJournal(journal)
        var changedHosts = false
        var changedTrust = false
        var changedRecord = false
        do {
            try hosts.replace(expected: before, with: after)
            changedHosts = true
            journal.phase = "Host entries were written"; try writeJournal(journal)
            do {
                journal.phase = "Certificate approval started; its result may be unknown"; try writeJournal(journal)
                try await certificates.install(request.certificateDER, hostnames: hostnames,
                                               policy: request.trustPolicy, replacingOwned: previous != nil)
                changedTrust = true
                journal.phase = "Certificate trust was written"; try writeJournal(journal)
            } catch {
                if case JerdError.partialChange = error { changedTrust = true }
                throw error
            }
            try PrivateFiles.write(try JSONEncoder().encode(next), to: recordURL)
            changedRecord = true
            journal.phase = "Registration was written"; try writeJournal(journal)
            try FileManager.default.removeItem(at: directory.appendingPathComponent("pending.json"))
        } catch {
            var recoveryErrors: [String] = []
            if !changedHosts, case JerdError.partialChange = error {
                journal.phase = "Host replacement needs recovery: \(error.localizedDescription)"
                try? writeJournal(journal)
                recoveryErrors.append(error.localizedDescription)
            }
            if case JerdError.approvalInterrupted = error {
                recoveryErrors.append("Certificate approval was interrupted. Its result is unknown; the recovery record was retained.")
            }
            if changedTrust {
                do {
                    if let previous { try await certificates.install(previous.certificateDER, hostnames: previous.hostnames, policy: previous.trustPolicy, replacingOwned: true) }
                    else { try await certificates.remove(request.certificateDER) }
                } catch { recoveryErrors.append(error.localizedDescription) }
            }
            if changedHosts {
                do { try hosts.replace(expected: after, with: before) }
                catch { recoveryErrors.append(error.localizedDescription) }
            }
            if changedRecord {
                do {
                    if let previous { try PrivateFiles.write(try JSONEncoder().encode(previous), to: recordURL) }
                    else { try FileManager.default.removeItem(at: recordURL) }
                } catch { recoveryErrors.append(error.localizedDescription) }
            }
            if recoveryErrors.isEmpty { try? FileManager.default.removeItem(at: directory.appendingPathComponent("pending.json")) }
            if !recoveryErrors.isEmpty {
                throw JerdError.invalid("Setup failed and needs recovery. The helper retained its backup. \(error.localizedDescription) \(recoveryErrors.joined(separator: " "))")
            }
            throw error
        }
    }

    public func remove(ownerUID: uid_t, trustManager: (any CertificateTrustManaging)? = nil) async throws {
        try beginMutation(); defer { mutation = false }
        let certificates = trustManager ?? self.certificates
        guard let record = try ownedRecord(ownerUID) else { return }
        let before = try hosts.read()
        let after = try HostsDocument.replacing(before, hostnames: [], expectedHostnames: record.hostnames)
        try PrivateFiles.write(before, to: directory.appendingPathComponent("hosts.previous"))
        var journal = Journal(operation: "Remove HTTPS", previous: record,
            previousBytes: try PrivateFiles.read(recordURL, limit: 131_072, owner: expectedFileOwner),
            intended: nil, hostsSHA256: InstallationCertificate.fingerprint(before), phase: "Prepared; system writes have not started")
        try writeJournal(journal)
        var changedHosts = false
        do {
            try hosts.replace(expected: before, with: after)
            changedHosts = true
            journal.phase = "Host entries were removed"; try writeJournal(journal)
            journal.phase = "Certificate removal started; its result may be unknown"; try writeJournal(journal)
            try await certificates.remove(record.certificateDER)
            journal.phase = "Certificate was removed"; try writeJournal(journal)
            try FileManager.default.removeItem(at: recordURL)
            journal.phase = "Registration was removed"; try writeJournal(journal)
            try FileManager.default.removeItem(at: directory.appendingPathComponent("pending.json"))
        } catch {
            var failures: [String] = []
            if !changedHosts, case JerdError.partialChange = error {
                journal.phase = "Host replacement needs recovery: \(error.localizedDescription)"
                try? writeJournal(journal)
                failures.append(error.localizedDescription)
            }
            if case JerdError.approvalInterrupted = error {
                failures.append("Certificate approval was interrupted. Inspect the retained recovery record before retrying.")
            }
            if changedHosts {
                do { try await certificates.install(record.certificateDER, hostnames: record.hostnames, policy: record.trustPolicy, replacingOwned: true) }
                catch { failures.append(error.localizedDescription) }
                do { try hosts.replace(expected: after, with: before) }
                catch { failures.append(error.localizedDescription) }
                do { try PrivateFiles.write(try JSONEncoder().encode(record), to: recordURL) }
                catch { failures.append(error.localizedDescription) }
            }
            if failures.isEmpty { try? FileManager.default.removeItem(at: directory.appendingPathComponent("pending.json")) }
            else { throw JerdError.unavailable("Removal needs recovery. The helper retained its backup. \(failures.joined(separator: " "))") }
            throw error
        }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("hosts.previous"))
    }

    private func ownedRecord(_ ownerUID: uid_t, allowPending: Bool = false) throws -> Registration? {
        guard allowPending || !FileManager.default.fileExists(atPath: pendingURL.path) else {
            throw JerdError.unavailable("A previous system setup was interrupted. A recovery record is retained in the helper directory. Do not overwrite it.")
        }
        guard FileManager.default.fileExists(atPath: recordURL.path) else { return nil }
        let record = try JSONDecoder().decode(Registration.self, from: PrivateFiles.read(recordURL, limit: 131_072, owner: expectedFileOwner))
        guard record.schemaVersion == 3, record.ownerUID == ownerUID else {
            throw JerdError.unavailable("The system setup belongs to another user or uses an unsupported version.")
        }
        return record
    }

    public func recover(_ approval: SystemRecoveryApproval, ownerUID: uid_t,
                        trustManager: (any CertificateTrustManaging)? = nil) async throws {
        try beginMutation(); defer { mutation = false }
        let certificates = trustManager ?? self.certificates
        let pending = try readPending(ownerUID)
        let report = try recoveryStatus(pending, ownerUID: ownerUID)
        guard approval.recordID == report.id else { throw JerdError.unavailable("The recovery record changed. Inspect it and approve recovery again.") }
        guard approval.action == .restorePrevious ? report.canRestore : report.canRemove else {
            throw JerdError.unavailable("The recorded system state needs manual inspection. No recovery change was made.")
        }
        let target = approval.action == .restorePrevious ? pending.previous : nil
        let current = try hosts.read()
        let after = try restoredHosts(current, pending: pending, target: target?.hostnames ?? [])
        // Keep the original journal and backup even if another recovery step fails.
        try PrivateFiles.write(pending.bytes, to: directory.appendingPathComponent("recovery.previous.json"))
        var journal = pending.journal
        journal?.phase = "Approved recovery started; inspect current state before retrying"
        if let journal { try writeJournal(journal) }
        try hosts.replace(expected: current, with: after)
        journal?.phase = "Recovery host entries were written; certificate change is pending"
        if let journal { try writeJournal(journal) }
        if let target {
            try await certificates.install(target.certificateDER, hostnames: target.hostnames,
                                           policy: target.trustPolicy, replacingOwned: true)
            journal?.phase = "Recovery certificate trust was written"
            if let journal { try writeJournal(journal) }
            if let bytes = pending.journal?.previousBytes { try PrivateFiles.write(bytes, to: recordURL) }
            else { try PrivateFiles.write(JSONEncoder().encode(target), to: recordURL) }
        } else {
            try await certificates.remove(pending.reference.certificateDER)
            journal?.phase = "Recovery certificate was removed"
            if let journal { try writeJournal(journal) }
            if FileManager.default.fileExists(atPath: recordURL.path) { try FileManager.default.removeItem(at: recordURL) }
        }
        try FileManager.default.removeItem(at: pendingURL)
    }

    private func recoveryStatus(_ pending: Pending, ownerUID: uid_t) throws -> SystemRecoveryStatus {
        var details = [String]()
        let current = try hosts.read()
        var recordKnown = true
        do {
            if let actual = try ownedRecord(ownerUID, allowPending: true), actual != pending.previous && actual != pending.intended {
                recordKnown = false
                details.append("The saved registration differs from this transaction. Inspect it manually.")
            }
        } catch { recordKnown = false; details.append(error.localizedDescription) }
        var backupValid = false
        if let journal = pending.journal {
            do {
                let backup = try PrivateFiles.read(directory.appendingPathComponent("hosts.previous"), limit: 1_048_576, owner: expectedFileOwner)
                backupValid = InstallationCertificate.fingerprint(backup) == journal.hostsSHA256
            } catch { details.append(error.localizedDescription) }
            details.append(backupValid ? "The original host-file backup is present and matches its record." : "The original host-file backup is missing or changed. Automatic restoration is blocked.")
        } else {
            details.append("This legacy record does not identify the interrupted operation. You can remove the recorded setup after approval, then enable HTTPS again.")
        }
        let canRemoveHosts = (try? restoredHosts(current, pending: pending, target: [])) != nil
        let canRestoreHosts = (try? restoredHosts(current, pending: pending, target: pending.previous?.hostnames ?? [])) != nil
        details.append(canRemoveHosts ? "The current Jerd host section matches a recorded state. Unrelated host entries will be retained." : "The Jerd host section changed outside this transaction. Inspect the host file manually.")
        let trusted = try? certificates.isInstalled(pending.reference.certificateDER, hostnames: pending.reference.hostnames, policy: pending.reference.trustPolicy)
        details.append(trusted == true ? "The recorded certificate trust is currently present." : "The recorded certificate trust is absent or could not be confirmed.")
        details.append("Recovery changes only the recorded Jerd host section, certificate, and registration. The operation can request macOS approval.")
        return SystemRecoveryStatus(id: pending.id, operation: pending.journal?.operation ?? "Interrupted legacy HTTPS setup",
            phase: pending.journal?.phase ?? "Unknown", details: details,
            canRestore: pending.journal != nil && backupValid && recordKnown && canRestoreHosts,
            canRemove: recordKnown && canRemoveHosts, installationID: pending.reference.installationID,
            certificateDER: pending.reference.certificateDER, previousHostnames: pending.previous?.hostnames ?? [],
            intendedHostnames: pending.intended?.hostnames ?? [],
            policies: Array(Set([pending.reference.trustPolicy] + (pending.previous.map { [$0.trustPolicy] } ?? []))))
    }

    private func restoredHosts(_ current: Data, pending: Pending, target: [String]) throws -> Data {
        for expected in [pending.previous?.hostnames ?? [], pending.intended?.hostnames ?? [], []] {
            if HostsDocument.containsRegistrations(expected, in: current) {
                return try HostsDocument.replacing(current, hostnames: target, expectedHostnames: expected)
            }
        }
        throw JerdError.unavailable("The current Jerd host section does not match the recovery record.")
    }

    private func readPending(_ owner: uid_t) throws -> Pending {
        let bytes = try PrivateFiles.read(pendingURL, limit: 262_144, owner: expectedFileOwner)
        let decoder = JSONDecoder()
        if let journal = try? decoder.decode(Journal.self, from: bytes) {
            guard journal.schemaVersion == 1, ["Configure HTTPS", "Remove HTTPS"].contains(journal.operation),
                  let reference = journal.intended ?? journal.previous else { throw JerdError.corruptConfiguration("The helper recovery record is invalid. It was preserved.") }
            try validateRecoveryOwner(reference, owner)
            for record in [journal.previous, journal.intended].compactMap({ $0 }) {
                try validateRecoveryOwner(record, owner)
                guard record.installationID == reference.installationID, record.certificateDER == reference.certificateDER else {
                    throw JerdError.corruptConfiguration("The recovery certificates do not match. Inspect the records manually.")
                }
            }
            if let previous = journal.previous {
                guard let data = journal.previousBytes, try decoder.decode(Registration.self, from: data) == previous else {
                    throw JerdError.corruptConfiguration("The previous registration does not match the recovery record.")
                }
            } else if journal.previousBytes != nil { throw JerdError.corruptConfiguration("The previous registration is invalid.") }
            return Pending(bytes: bytes, journal: journal, reference: reference, previous: journal.previous, intended: journal.intended)
        }
        let legacy = try decoder.decode(Registration.self, from: bytes)
        try validateRecoveryOwner(legacy, owner)
        let current = try ownedRecord(owner, allowPending: true)
        if let current {
            guard current.installationID == legacy.installationID, current.certificateDER == legacy.certificateDER else {
                throw JerdError.corruptConfiguration("The legacy recovery record differs from the registration. Inspect both records manually.")
            }
        }
        return Pending(bytes: bytes, journal: nil, reference: legacy, previous: current, intended: legacy)
    }

    private func validateRecoveryOwner(_ record: Registration, _ owner: uid_t) throws {
        guard owner != 0, record.ownerUID == owner else { throw JerdError.unavailable("This recovery record belongs to another user.") }
        try certificates.validate(record.certificateDER, installationID: record.installationID)
    }

    private func writeJournal(_ journal: Journal) throws { try PrivateFiles.write(JSONEncoder().encode(journal), to: pendingURL) }
    private func beginMutation() throws {
        guard !mutation else { throw JerdError.unavailable("Wait for the current system operation to finish.") }
        mutation = true
    }

    private func prepareDirectory() throws {
        try PrivateFiles.directory(directory)
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_uid == expectedFileOwner else {
            throw JerdError.invalid("The helper data directory has an invalid owner.")
        }
    }
}
