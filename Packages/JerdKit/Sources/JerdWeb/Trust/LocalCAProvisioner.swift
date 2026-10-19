import CryptoKit
import Foundation
import JerdFoundation

/// Makes the installation CA when it is missing, then loads and checks it.
///
/// Jerd makes the CA itself (`LocalRootTemplate`), so that it may sign only `.test` names. An
/// installation that has the CA that Caddy made keeps it (`ActiveAuthority`). Making the CA never
/// installs trust: approval of the CA is the helper's job, not this type's.
package struct LocalCAProvisioner: Sendable {
    private let environment: EnvironmentLayout
    private let now: @Sendable () -> Date

    package init(environment: EnvironmentLayout, now: @escaping @Sendable () -> Date = { Date() }) {
        self.environment = environment
        self.now = now
    }

    /// The installation CA, made first when the active root is absent.
    package func provision(installationID: UUID) throws -> LocalCertificateAuthority {
        if FileProbe.presence(at: ActiveAuthority.rootCertificateFile(environment)) == .absent {
            try create(installationID: installationID)
        }
        return try load(installationID: installationID)
    }

    /// The saved installation CA, read strictly and checked against the installation ID.
    package func load(installationID: UUID) throws -> LocalCertificateAuthority {
        let authority = try LocalCertificateAuthority.read(ActiveAuthority.rootCertificateFile(environment))
        try InstallationCertificate.validate(authority.der, installationID: installationID)
        if ActiveAuthority.resolve(environment, installationID: installationID).providesRoot {
            try RootKeyCheck.requireMatch(certificate: authority.der, keyFile: environment.constrainedRootKeyFile)
        }
        return authority
    }

    /// Writes the key first and the certificate last, so that every `root.crt` has its key. The
    /// intermediate of an earlier root goes first: Caddy would load it, and the new root did not
    /// sign it.
    /// Creation holds the web environment lock, so it cannot race the engine or recovery of
    /// another Jerd instance; a CA that another instance made meanwhile is kept.
    private func create(installationID: UUID) throws {
        for folder in [
            environment.configurationDirectory, environment.certificatesDirectory, environment.processesDirectory,
        ] {
            try OwnedDirectory.create(folder)
        }
        let lock = try InstanceLock.acquire(at: environment.recoveryLockFile, messages: WebEnvironmentLock.messages)
        defer { lock.release() }
        guard FileProbe.presence(at: environment.constrainedRootCertificateFile) == .absent else { return }
        let folder = environment.authorityDirectory(EnvironmentLayout.constrainedAuthorityID)
        try OwnedDirectory.create(folder, within: environment.certificatesDirectory)
        for name in ["intermediate.crt", "intermediate.key"] {
            let file = folder.appendingPathComponent(name, isDirectory: false)
            if FileProbe.presence(at: file) != .absent { try FileManager.default.removeItem(at: file) }
        }
        let key = P256.Signing.PrivateKey()
        try AtomicFile.write(Data(key.pemRepresentation.utf8), to: environment.constrainedRootKeyFile)
        let name = LocalAuthority.constrainedInstallation(installationID).name
        let der = try LocalRootTemplate.certificate(commonName: name, key: key, now: now())
        try AtomicFile.write(Self.pem(der), to: environment.constrainedRootCertificateFile)
    }

    static func pem(_ der: Data) -> Data {
        let body = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return Data("-----BEGIN CERTIFICATE-----\n\(body)\n-----END CERTIFICATE-----\n".utf8)
    }
}
