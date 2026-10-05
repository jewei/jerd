/// Adds or removes the CA and its admin trust. Each change needs the app's consent.
public protocol CertificateTrustChanging: Sendable {
    /// Adds the CA to the system keychain and applies the trust.
    ///
    /// - Parameter replacingOwned: the CA belongs to Jerd's recorded setup, so an existing keychain
    ///   item is expected and matching trust needs no new approval.
    func install(_ trust: CertificateTrust, replacingOwned: Bool) async throws
    /// Removes the trust, then the keychain item of exactly this CA.
    func remove(_ certificate: InstallationCertificate) async throws
}
