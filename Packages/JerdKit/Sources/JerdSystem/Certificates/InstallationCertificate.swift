import Foundation
import Security

/// The validated CA of one Jerd installation: its installation ID and DER bytes.
public struct InstallationCertificate: Hashable, Sendable {
    public let installationID: UUID
    public let der: Data

    /// Validates `der` with `CertificateIdentity.validateInstallationCA`.
    public init(installationID: UUID, der: Data) throws {
        _ = try CertificateIdentity.validateInstallationCA(der, installationID: installationID)
        self.installationID = installationID
        self.der = der
    }

    /// Decodes and validates a PEM certificate, for example Caddy's `root.crt`.
    public init(installationID: UUID, pem: Data) throws {
        try self.init(installationID: installationID, der: CertificateIdentity.decodePEM(pem))
    }

    /// The lowercase SHA-256 of the DER bytes, as shown to the user.
    public var sha256: String { CertificateIdentity.sha256Hex(der) }

    /// A `SecCertificate` of the validated bytes.
    public var secCertificate: SecCertificate? { SecCertificateCreateWithData(nil, der as CFData) }
}
