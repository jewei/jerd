import Foundation
import JerdFoundation

/// What the user approved for one operation: one CA, a set of hostnames, and the trust policies.
///
/// A reverse call may set trust only for this CA, a non-empty subset of the hostnames without
/// repeats, and an approved policy. It may always remove the trust of this CA, because a rollback
/// or a removal needs that (the old `allowRemoval` flag was always true in production).
public struct ConsentScope: Equatable, Sendable {
    public let certificateDER: Data
    public let hostnames: Set<String>
    public let policies: Set<CertificateTrustPolicy>

    /// Validates every hostname. The certificate is already validated.
    public init(certificate: InstallationCertificate, hostnames: [String], policies: Set<CertificateTrustPolicy>) throws
    {
        certificateDER = certificate.der
        self.hostnames = Set(try hostnames.map { try HostnamePolicy.validate($0).value })
        self.policies = policies
    }

    public func allows(_ request: TrustConsentRequest) -> Bool {
        guard request.certificateDER == certificateDER else { return false }
        guard let requested = request.hostnames else { return true }
        return policies.contains(request.policy) && !requested.isEmpty && Set(requested).count == requested.count
            && Set(requested).isSubset(of: hostnames)
    }
}
