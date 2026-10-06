import Foundation

/// The helper's report of the setup of the calling user.
///
/// JSON keys: `hostnames`, `installationID?`, `certificateSHA256?`, `certificateDER?`,
/// `hostsConfigured`, `trustConfigured`, `trustPolicy`, `recovery?`, and (since the rewrite)
/// `operationInProgress?`. Older apps ignore the new optional key.
public struct SystemSetupStatus: Codable, Equatable, Sendable {
    public var hostnames: [String]
    public var installationID: UUID?
    public var certificateSHA256: String?
    public var certificateDER: Data?
    public var hostsConfigured: Bool
    public var trustConfigured: Bool
    public var trustPolicy: CertificateTrustPolicy
    /// An interrupted transaction that needs an approved recovery.
    public var recovery: SystemRecoveryStatus?
    /// The name of a transaction that is running now, for example "Configure HTTPS". It is not interrupted.
    public var operationInProgress: String?

    public init(
        hostnames: [String] = [], installationID: UUID? = nil, certificateSHA256: String? = nil,
        certificateDER: Data? = nil, hostsConfigured: Bool = false, trustConfigured: Bool = false,
        trustPolicy: CertificateTrustPolicy = .hostnames, recovery: SystemRecoveryStatus? = nil,
        operationInProgress: String? = nil
    ) {
        self.hostnames = hostnames
        self.installationID = installationID
        self.certificateSHA256 = certificateSHA256
        self.certificateDER = certificateDER
        self.hostsConfigured = hostsConfigured
        self.trustConfigured = trustConfigured
        self.trustPolicy = trustPolicy
        self.recovery = recovery
        self.operationInProgress = operationInProgress
    }

    /// The status of a user without a setup.
    public static let empty = SystemSetupStatus()

    /// True when hosts and trust are configured with the server TLS policy, and nothing is pending.
    public var isReadyForServing: Bool {
        hostsConfigured && trustConfigured && trustPolicy == .serverTLS && recovery == nil
            && operationInProgress == nil
    }
}
