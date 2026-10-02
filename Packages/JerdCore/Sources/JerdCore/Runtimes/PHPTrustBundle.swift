import Foundation
import Security

/// Makes the approved local CA available to PHP's file-based TLS clients.
public struct PHPTrustBundle: Sendable {
    private let isTrusted: @Sendable (Data) throws -> Bool

    public init() { isTrusted = Self.systemTrust }
    init(isTrusted: @escaping @Sendable (Data) throws -> Bool) { self.isTrusted = isTrusted }

    public func forCLI(applicationDirectory: URL) throws -> URL? {
        let environment = applicationDirectory.appendingPathComponent("environment")
        let identity = environment.appendingPathComponent("installation-id")
        guard PrivateFiles.exists(identity) else { return nil }
        guard let id = UUID(uuidString: String(decoding: try PrivateFiles.read(identity, limit: 128), as: UTF8.self)) else {
            throw JerdError.corruptConfiguration("The HTTPS installation identity is invalid. It was preserved.")
        }
        let paths = EnginePaths(root: environment, socketDirectory: environment, installationID: id)
        return try prepare(paths: paths, directory: applicationDirectory.appendingPathComponent("runtimes/configuration"))
    }

    func prepare(paths: EnginePaths, directory: URL) throws -> URL? {
        guard PrivateFiles.exists(paths.rootCertificate) else { return nil }
        let pem = try PrivateFiles.read(paths.rootCertificate, limit: 65_536)
        let der = try InstallationCertificate.decodePEM(pem)
        if let identity = paths.installationID { _ = try InstallationCertificate.validate(der, installationID: identity) }
        guard try isTrusted(der) else { return nil }
        // Retain the public roots used by the managed OpenSSL PHP builds.
        // This file is owned by macOS; Jerd only reads it.
        let roots = try PrivateFiles.read(URL(fileURLWithPath: "/etc/ssl/cert.pem"), limit: 2_097_152, owner: 0)
        guard roots.range(of: Data("-----BEGIN CERTIFICATE-----".utf8)) != nil else {
            throw JerdError.unavailable("The macOS CA file contains no certificates.")
        }
        let bundle = roots + Data("\n".utf8) + pem
        try PrivateFiles.directory(directory)
        let file = directory.appendingPathComponent("php-ca.pem")
        if try !PrivateFiles.exists(file) || PrivateFiles.read(file, limit: 2_162_689) != bundle {
            try PrivateFiles.write(bundle, to: file)
        }
        return file
    }

    private static func systemTrust(_ der: Data) throws -> Bool {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw JerdError.invalid("The local CA certificate is invalid.")
        }
        // User settings take precedence. Do not export a denied or restricted
        // certificate into a PEM file, which cannot express those restrictions.
        for domain in [SecTrustSettingsDomain.user, .admin] {
            var settings: CFArray?
            let status = SecTrustSettingsCopyTrustSettings(certificate, domain, &settings)
            if status == errSecItemNotFound { continue }
            guard status == errSecSuccess else {
                throw JerdError.unavailable("Cannot read the local CA trust settings (\(status)).")
            }
            guard let entries = settings as? [[String: Any]] else { return false }
            return accepts(entries)
        }
        return false
    }

    static func accepts(_ entries: [[String: Any]]) -> Bool {
        // The hostname argument is validated but unused by the serverTLS policy.
        CertificateTrustSettings.matches(entries, policy: .serverTLS, hostnames: ["jerd.test"])
    }
}
