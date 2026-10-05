import Foundation
import JerdFoundation

/// The committed setup of one user, saved as `registration.json`.
///
/// Read: version 1 (`hostname`, one string), version 2 (`hostnames`), and version 3 (`hostnames` and
/// `trustPolicy`). Versions 1 and 2 always mean the `hostnames` policy, so an old record never gets
/// broader trust. Write: always version 3. Hostnames are validated, lowercase, unique, and sorted.
/// Equality ignores the stored version.
public struct RegistrationRecord: Codable, Equatable, Sendable {
    /// The version that `encode` writes.
    public static let currentVersion = 3

    public let ownerUID: uid_t
    public let installationID: UUID
    public let hostnames: ValidatedHostnames
    public let certificateDER: Data
    public let trustPolicy: CertificateTrustPolicy

    public init(
        ownerUID: uid_t, installationID: UUID, hostnames: ValidatedHostnames, certificateDER: Data,
        trustPolicy: CertificateTrustPolicy
    ) {
        self.ownerUID = ownerUID
        self.installationID = installationID
        self.hostnames = hostnames
        self.certificateDER = certificateDER
        self.trustPolicy = trustPolicy
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, ownerUID, installationID, hostnames, hostname, certificateDER, trustPolicy
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .schemaVersion)
        guard (1...Self.currentVersion).contains(version) else {
            throw JerdError.corrupt("The helper registration version is unsupported.")
        }
        ownerUID = try values.decode(uid_t.self, forKey: .ownerUID)
        installationID = try values.decode(UUID.self, forKey: .installationID)
        certificateDER = try values.decode(Data.self, forKey: .certificateDER)
        let names =
            version == 1
            ? [try values.decode(String.self, forKey: .hostname)] : try values.decode([String].self, forKey: .hostnames)
        hostnames = try ValidatedHostnames(names)
        trustPolicy = version < 3 ? .hostnames : try values.decode(CertificateTrustPolicy.self, forKey: .trustPolicy)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.currentVersion, forKey: .schemaVersion)
        try values.encode(ownerUID, forKey: .ownerUID)
        try values.encode(installationID, forKey: .installationID)
        try values.encode(hostnames, forKey: .hostnames)
        try values.encode(certificateDER, forKey: .certificateDER)
        try values.encode(trustPolicy, forKey: .trustPolicy)
    }

    /// The validated trust of this setup.
    public func trust() throws -> CertificateTrust {
        CertificateTrust(
            certificate: try InstallationCertificate(installationID: installationID, der: certificateDER),
            hostnames: hostnames, policy: trustPolicy)
    }

    /// True when `other` uses the same installation and the same CA bytes.
    func hasSameCertificate(as other: RegistrationRecord) -> Bool {
        installationID == other.installationID && certificateDER == other.certificateDER
    }
}
