import Foundation

/// The reverse-call payload. JSON keys: `certificateDER`, `hostnames?`, `policy`.
///
/// A list of hostnames sets trust for the approved setup. An absent list removes the trust of the CA.
public struct TrustConsentRequest: Codable, Equatable, Sendable {
    public let certificateDER: Data
    public let hostnames: [String]?
    public let policy: CertificateTrustPolicy

    public init(certificateDER: Data, hostnames: [String]?, policy: CertificateTrustPolicy) {
        self.certificateDER = certificateDER
        self.hostnames = hostnames
        self.policy = policy
    }

    /// A removal request. The policy is `hostnames`, as older helpers sent it; the app ignores it.
    public static func removal(of certificateDER: Data) -> TrustConsentRequest {
        TrustConsentRequest(certificateDER: certificateDER, hostnames: nil, policy: .hostnames)
    }
}
