import Foundation
import JerdFoundation

/// This installation's CA as an approval names it: the installation ID and the CA fingerprint.
public struct InstallationAuthority: Equatable, Sendable {
    public let installationID: UUID
    /// Lowercase hexadecimal SHA-256 of the CA certificate, in the form that the helper reports.
    public let fingerprint: String
    /// False for the CA that Caddy made, which can sign any name: the Sites page then offers the
    /// update to Jerd's CA for `.test` names.
    public let signsOnlyTestNames: Bool

    public init(installationID: UUID, fingerprint: String, signsOnlyTestNames: Bool = true) {
        self.installationID = installationID
        self.fingerprint = fingerprint
        self.signsOnlyTestNames = signsOnlyTestNames
    }

    /// Reads the installation ID and `root.crt` of `environment`.
    ///
    /// - Returns: nil when the installation ID or `root.crt` is absent (the CA must be prepared).
    /// - Throws: for a corrupt file, which stays in place.
    public static func read(_ environment: EnvironmentLayout) throws -> InstallationAuthority? {
        guard let installationID = try InstallationIdentity(environment: environment).read(),
            FileProbe.presence(at: ActiveAuthority.rootCertificateFile(environment)).mayExist
        else { return nil }
        let authority = try LocalCertificateAuthority.read(ActiveAuthority.rootCertificateFile(environment))
        // The flag only offers the CA update. A CA that cannot be inspected counts as able to sign
        // any name, so the start path never fails on it.
        let inspection = try? NameConstraintsInspection.inspect(certificate: authority.der)
        return InstallationAuthority(
            installationID: installationID, fingerprint: authority.fingerprint,
            signsOnlyTestNames: inspection == .limitedToTest)
    }
}
