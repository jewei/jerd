/// Reads whether the admin trust settings of a CA match a setup. It changes nothing.
public protocol CertificateTrustInspecting: Sendable {
    func isInstalled(_ trust: CertificateTrust) throws -> Bool
}
