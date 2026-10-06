import Foundation
import JerdFoundation

/// This installation's CA as an approval names it: the installation ID and the CA fingerprint.
public struct InstallationAuthority: Equatable, Sendable {
    public let installationID: UUID
    /// Lowercase hexadecimal SHA-256 of the CA certificate, in the form that the helper reports.
    public let fingerprint: String

    public init(installationID: UUID, fingerprint: String) {
        self.installationID = installationID
        self.fingerprint = fingerprint
    }

    /// Reads the installation ID and `root.crt` of `environment`.
    ///
    /// - Returns: nil when the installation ID or `root.crt` is absent (the CA must be prepared).
    /// - Throws: for a corrupt file, which stays in place.
    public static func read(_ environment: EnvironmentLayout) throws -> InstallationAuthority? {
        guard let installationID = try InstallationIdentity(environment: environment).read(),
            FileProbe.presence(at: environment.rootCertificateFile).mayExist
        else { return nil }
        let authority = try LocalCertificateAuthority.read(environment.rootCertificateFile)
        return InstallationAuthority(installationID: installationID, fingerprint: authority.fingerprint)
    }
}
