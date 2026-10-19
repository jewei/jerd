import Foundation
import JerdFoundation

/// What the user approved for one operation: one CA, a set of hostnames, and the trust policies.
///
/// A reverse call may set trust only for this CA, a non-empty subset of the hostnames without
/// repeats, and an approved policy. It may always remove the trust of this CA, because a rollback
/// or a removal needs that (the old `allowRemoval` flag was always true in production).
///
/// A CA replacement also names the retiring CA: the operation removes it, and a rollback trusts it
/// again with the same hostnames and policies. No other CA is ever allowed.
package struct ConsentScope: Equatable, Sendable {
    package let certificateDER: Data
    package let retiringCertificateDER: Data?
    package let hostnames: Set<String>
    package let policies: Set<CertificateTrustPolicy>

    /// Validates every hostname. The certificate is already validated.
    package init(
        certificate: InstallationCertificate, hostnames: [String], policies: Set<CertificateTrustPolicy>,
        retiring: InstallationCertificate? = nil
    ) throws {
        certificateDER = certificate.der
        retiringCertificateDER = retiring?.der
        self.hostnames = Set(try hostnames.map { try HostnamePolicy.validate($0).value })
        self.policies = policies
    }

    package func allows(_ request: TrustConsentRequest) -> Bool {
        guard request.certificateDER == certificateDER || request.certificateDER == retiringCertificateDER
        else { return false }
        guard let requested = request.hostnames else { return true }
        return policies.contains(request.policy) && !requested.isEmpty && Set(requested).count == requested.count
            && Set(requested).isSubset(of: hostnames)
    }
}
