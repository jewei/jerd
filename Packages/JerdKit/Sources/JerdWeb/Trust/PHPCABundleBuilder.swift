import Darwin
import Foundation
import JerdFoundation

/// Makes the approved local CA available to PHP's file-based TLS clients (cURL and OpenSSL).
///
/// The bundle is the macOS public roots followed by the local CA. It exists only while macOS
/// trusts the CA for server TLS without limits; a change takes effect at the next web start or
/// CLI call. Both FPM (`environment/configuration/php-ca.pem`) and the CLI
/// (`runtimes/configuration/php-ca.pem`) use this builder.
public struct PHPCABundleBuilder: Sendable {
    /// The public roots that the managed OpenSSL PHP builds use. macOS owns this file.
    public static let systemRootsFile = URL(fileURLWithPath: "/etc/ssl/cert.pem")
    /// The read limit of the system roots.
    public static let systemRootsLimit = 2_097_152
    /// The read limit of an existing bundle: the roots, a newline, and a certificate file.
    public static let bundleLimit = systemRootsLimit + 1 + LocalCertificateAuthority.fileLimit

    private let trust: any TrustDecisionPort
    private let systemRoots: URL
    private let systemRootsOwner: uid_t

    public init(
        trust: any TrustDecisionPort = SystemTrustDecision(), systemRoots: URL = systemRootsFile,
        systemRootsOwner: uid_t = 0
    ) {
        self.trust = trust
        self.systemRoots = systemRoots
        self.systemRootsOwner = systemRootsOwner
    }

    /// Writes `output` when it is absent or different, and returns it. Nil when the CA does not
    /// exist yet or macOS does not trust it for server TLS.
    ///
    /// - Parameter installationID: when set, the CA must be this installation's root CA.
    public func prepare(rootCertificate: URL, installationID: UUID?, output: URL) throws -> URL? {
        guard FileProbe.presence(at: rootCertificate).mayExist else { return nil }
        let authority = try LocalCertificateAuthority.read(rootCertificate)
        if let installationID { try InstallationCertificate.validate(authority.der, installationID: installationID) }
        guard try trust.isTrustedForServerTLS(authority.der) else { return nil }
        let roots = try AtomicFile.read(systemRoots, limit: Self.systemRootsLimit, owner: systemRootsOwner)
        guard roots.range(of: Data("-----BEGIN CERTIFICATE-----".utf8)) != nil else {
            throw JerdError.unavailable("The macOS CA file contains no certificates.")
        }
        let bundle = roots + Data("\n".utf8) + authority.pem
        try OwnedDirectory.create(output.deletingLastPathComponent())
        let isCurrent =
            try FileProbe.presence(at: output) != .absent
            && AtomicFile.read(output, limit: Self.bundleLimit) == bundle
        if !isCurrent { try AtomicFile.write(bundle, to: output) }
        return output
    }

    /// The CLI bundle of the installation CA in `layout`. Nil before the first HTTPS setup.
    /// - Throws: `.corrupt` for an invalid installation identity, and every error of `prepare`.
    public func prepareForCLI(layout: DataLayout) throws -> URL? {
        guard let installationID = try InstallationIdentity(environment: layout.environment).read() else { return nil }
        return try prepare(
            rootCertificate: layout.environment.rootCertificateFile, installationID: installationID,
            output: layout.runtimes.cliCABundleFile)
    }
}
