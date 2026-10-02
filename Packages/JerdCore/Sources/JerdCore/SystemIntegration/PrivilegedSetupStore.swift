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
    private struct Registration: Codable {
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
    private let directory: URL
    private let expectedFileOwner: uid_t
    private let hosts: AtomicHostsFile
    private let certificates: any CertificateTrustManaging
    private var recordURL: URL { directory.appendingPathComponent("registration.json") }

    public init(directory: URL, expectedFileOwner: uid_t, hosts: AtomicHostsFile,
                certificates: any CertificateTrustManaging) {
        self.directory = directory; self.expectedFileOwner = expectedFileOwner
        self.hosts = hosts; self.certificates = certificates
    }

    public func status(ownerUID: uid_t) throws -> SystemSetupStatus {
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
        try PrivateFiles.write(try JSONEncoder().encode(next), to: directory.appendingPathComponent("pending.json"))
        var changedHosts = false
        var changedTrust = false
        var changedRecord = false
        do {
            try hosts.replace(expected: before, with: after)
            changedHosts = true
            changedTrust = true
            try await certificates.install(request.certificateDER, hostnames: hostnames, policy: request.trustPolicy, replacingOwned: previous != nil)
            try PrivateFiles.write(try JSONEncoder().encode(next), to: recordURL)
            changedRecord = true
            try FileManager.default.removeItem(at: directory.appendingPathComponent("pending.json"))
        } catch {
            var recoveryErrors: [String] = []
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
        let certificates = trustManager ?? self.certificates
        guard let record = try ownedRecord(ownerUID) else { return }
        let before = try hosts.read()
        let after = try HostsDocument.replacing(before, hostnames: [], expectedHostnames: record.hostnames)
        try PrivateFiles.write(before, to: directory.appendingPathComponent("hosts.previous"))
        try PrivateFiles.write(try JSONEncoder().encode(record), to: directory.appendingPathComponent("pending.json"))
        var changedHosts = false
        do {
            try hosts.replace(expected: before, with: after)
            changedHosts = true
            try await certificates.remove(record.certificateDER)
            try FileManager.default.removeItem(at: recordURL)
            try FileManager.default.removeItem(at: directory.appendingPathComponent("pending.json"))
        } catch {
            var failures: [String] = []
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

    private func ownedRecord(_ ownerUID: uid_t) throws -> Registration? {
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending.json").path) else {
            throw JerdError.unavailable("A previous system setup was interrupted. A recovery record is retained in the helper directory. Do not overwrite it.")
        }
        guard FileManager.default.fileExists(atPath: recordURL.path) else { return nil }
        var info = stat()
        guard lstat(recordURL.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == expectedFileOwner, info.st_size <= 131_072 else {
            throw JerdError.corruptConfiguration("The helper registration file has an invalid owner, type, or size.")
        }
        let record = try JSONDecoder().decode(Registration.self, from: Data(contentsOf: recordURL))
        guard record.schemaVersion == 3, record.ownerUID == ownerUID else {
            throw JerdError.unavailable("The system setup belongs to another user or uses an unsupported version.")
        }
        return record
    }

    private func prepareDirectory() throws {
        try PrivateFiles.directory(directory)
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_uid == expectedFileOwner else {
            throw JerdError.invalid("The helper data directory has an invalid owner.")
        }
    }
}
