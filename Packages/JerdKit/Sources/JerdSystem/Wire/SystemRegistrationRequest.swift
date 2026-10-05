import Foundation

/// The configure payload: the hostnames and the installation CA that the user approved.
///
/// JSON keys: `installationID`, `hostnames`, `certificateDER`, `trustPolicy`. All are required.
public struct SystemRegistrationRequest: Codable, Equatable, Sendable {
    public let installationID: UUID
    public let hostnames: [String]
    public let certificateDER: Data
    public let trustPolicy: CertificateTrustPolicy

    public init(installationID: UUID, hostnames: [String], certificateDER: Data, trustPolicy: CertificateTrustPolicy) {
        self.installationID = installationID
        self.hostnames = hostnames
        self.certificateDER = certificateDER
        self.trustPolicy = trustPolicy
    }
}
