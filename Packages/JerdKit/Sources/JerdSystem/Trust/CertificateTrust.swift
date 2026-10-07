/// The trust that one setup gives its CA: the certificate, the approved hostnames, and the policy.
public struct CertificateTrust: Hashable, Sendable {
    public let certificate: InstallationCertificate
    public let hostnames: ValidatedHostnames
    public let policy: CertificateTrustPolicy

    public init(certificate: InstallationCertificate, hostnames: ValidatedHostnames, policy: CertificateTrustPolicy) {
        self.certificate = certificate
        self.hostnames = hostnames
        self.policy = policy
    }

    /// The trust settings that the policy produces.
    public var scope: TrustScope { TrustScope(policy: policy, hostnames: hostnames) }

    /// The reverse-call payload that asks the app to apply this trust.
    public var consentRequest: TrustConsentRequest {
        TrustConsentRequest(certificateDER: certificate.der, hostnames: hostnames.strings, policy: policy)
    }
}
