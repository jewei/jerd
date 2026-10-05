import Foundation

/// A request to the helper: map these hostnames to loopback and trust this installation CA.
public struct HTTPSRegistration: Equatable, Sendable {
    public let installationID: UUID
    /// Validated, unique, sorted hostnames.
    public let hostnames: [String]
    public let certificateDER: Data
    public let trustPolicy: HTTPSTrustPolicy

    public init(installationID: UUID, hostnames: [String], certificateDER: Data, trustPolicy: HTTPSTrustPolicy) {
        self.installationID = installationID
        self.hostnames = hostnames
        self.certificateDER = certificateDER
        self.trustPolicy = trustPolicy
    }
}
