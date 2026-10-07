import Foundation

/// What the privileged helper reports about the approved HTTPS setup, as the web layer needs it.
public struct HTTPSSetupStatus: Equatable, Sendable {
    /// The approved hostnames, sorted.
    public var hostnames: [String]
    public var installationID: UUID?
    /// Lowercase hexadecimal SHA-256 of the approved CA certificate.
    public var certificateSHA256: String?
    public var certificateDER: Data?
    public var hostsConfigured: Bool
    public var trustConfigured: Bool
    public var trustPolicy: HTTPSTrustPolicy
    /// True while an interrupted setup waits for approved recovery.
    public var hasPendingRecovery: Bool

    public init(
        hostnames: [String] = [], installationID: UUID? = nil, certificateSHA256: String? = nil,
        certificateDER: Data? = nil, hostsConfigured: Bool = false, trustConfigured: Bool = false,
        trustPolicy: HTTPSTrustPolicy = .hostnames, hasPendingRecovery: Bool = false
    ) {
        self.hostnames = hostnames
        self.installationID = installationID
        self.certificateSHA256 = certificateSHA256
        self.certificateDER = certificateDER
        self.hostsConfigured = hostsConfigured
        self.trustConfigured = trustConfigured
        self.trustPolicy = trustPolicy
        self.hasPendingRecovery = hasPendingRecovery
    }

    /// The registration that recreates this status, or nil when it has no setup to recreate.
    public var registration: HTTPSRegistration? {
        guard let installationID, let certificateDER, !hostnames.isEmpty else { return nil }
        return HTTPSRegistration(
            installationID: installationID, hostnames: hostnames, certificateDER: certificateDER,
            trustPolicy: trustPolicy)
    }
}
