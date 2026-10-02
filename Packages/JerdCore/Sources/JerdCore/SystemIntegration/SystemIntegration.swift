import Foundation
import Security
import CryptoKit

public enum SystemService {
    public static let name = "dev.jerd.helper"
    public static let plistName = "dev.jerd.helper.plist"
    public static let appIdentifier = "dev.jerd.app"
    public static let helperIdentifier = "dev.jerd.helper"

    public static func signingRequirement(identifier: String, teamID: String) throws -> String {
        guard teamID.count == 10, teamID.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }),
              [appIdentifier, helperIdentifier].contains(identifier) else {
            throw JerdError.invalid("A valid Apple signing team is required for system setup.")
        }
        let value = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\" and !entitlement[\"com.apple.security.get-task-allow\"] exists"
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(value as CFString, [], &requirement) == errSecSuccess else {
            throw JerdError.invalid("Cannot construct the helper signing requirement.")
        }
        return value
    }

    public static func currentTeamID() throws -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String else {
            throw JerdError.unavailable("System setup requires an Apple-signed Jerd build. Use the signed build instructions in README.")
        }
        return team
    }
}

public enum CertificateTrustPolicy: String, Codable, Sendable {
    case hostnames
    case serverTLS
}

public struct SystemRegistrationRequest: Codable, Sendable {
    public let installationID: UUID
    public let hostnames: [String]
    public let certificateDER: Data
    public let trustPolicy: CertificateTrustPolicy
    public init(installationID: UUID, hostnames: [String], certificateDER: Data,
                trustPolicy: CertificateTrustPolicy = .hostnames) {
        self.installationID = installationID; self.hostnames = hostnames; self.certificateDER = certificateDER
        self.trustPolicy = trustPolicy
    }
    public init(installationID: UUID, hostname: String, certificateDER: Data) {
        self.init(installationID: installationID, hostnames: [hostname], certificateDER: certificateDER)
    }
}

public struct SystemSetupStatus: Codable, Equatable, Sendable {
    public var hostnames: [String]
    public var hostname: String? { hostnames.first }
    public var installationID: UUID?
    public var certificateSHA256: String?
    public var certificateDER: Data?
    public var hostsConfigured: Bool
    public var trustConfigured: Bool
    public var trustPolicy: CertificateTrustPolicy
    public var recovery: SystemRecoveryStatus?
    public init(hostnames: [String], installationID: UUID? = nil, certificateSHA256: String? = nil,
                certificateDER: Data? = nil, hostsConfigured: Bool = false, trustConfigured: Bool = false,
                trustPolicy: CertificateTrustPolicy = .hostnames) {
        self.hostnames = hostnames; self.installationID = installationID; self.certificateSHA256 = certificateSHA256
        self.certificateDER = certificateDER
        self.hostsConfigured = hostsConfigured; self.trustConfigured = trustConfigured
        self.trustPolicy = trustPolicy
    }
    public init(hostname: String? = nil, installationID: UUID? = nil, certificateSHA256: String? = nil,
                certificateDER: Data? = nil, hostsConfigured: Bool = false, trustConfigured: Bool = false,
                trustPolicy: CertificateTrustPolicy = .hostnames) {
        self.init(hostnames: hostname.map { [$0] } ?? [], installationID: installationID,
                  certificateSHA256: certificateSHA256, certificateDER: certificateDER,
                  hostsConfigured: hostsConfigured, trustConfigured: trustConfigured, trustPolicy: trustPolicy)
    }
}

public enum SystemRecoveryAction: String, Codable, Sendable {
    case restorePrevious, removeSetup
}

public struct SystemRecoveryApproval: Codable, Sendable {
    public let recordID: String
    public let action: SystemRecoveryAction
    public init(recordID: String, action: SystemRecoveryAction) { self.recordID = recordID; self.action = action }
}

public struct SystemRecoveryStatus: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let operation: String
    public let phase: String
    public let details: [String]
    public let canRestore: Bool
    public let canRemove: Bool
    public let installationID: UUID
    public let certificateDER: Data
    public let previousHostnames: [String]
    public let intendedHostnames: [String]
    public let policies: [CertificateTrustPolicy]
    public var fingerprint: String { InstallationCertificate.fingerprint(certificateDER) }
}

public struct TrustConsentRequest: Codable, Sendable {
    public let certificateDER: Data
    /// A nonempty list identifies the approved setup. Nil removes this certificate's trust.
    public let hostnames: [String]?
    public let policy: CertificateTrustPolicy
    public init(certificateDER: Data, hostnames: [String]?, policy: CertificateTrustPolicy = .hostnames) {
        self.certificateDER = certificateDER; self.hostnames = hostnames; self.policy = policy
    }
    public init(certificateDER: Data, hostname: String?) {
        self.init(certificateDER: certificateDER, hostnames: hostname.map { [$0] })
    }
}

@objc public protocol JerdTrustConsentProtocol {
    func changeTrust(_ request: Data, reply: @escaping @Sendable (Int32) -> Void)
}

@objc public protocol JerdHelperProtocol {
    func status(reply: @escaping @Sendable (Data?, String?) -> Void)
    func configureSite(_ request: Data, reply: @escaping @Sendable (String?) -> Void)
    func acquireListeners(reply: @escaping @Sendable (FileHandle?, FileHandle?, String?) -> Void)
    func releaseListeners(reply: @escaping @Sendable () -> Void)
    func removeSetup(reply: @escaping @Sendable (String?) -> Void)
    func recoverSetup(_ approval: Data, reply: @escaping @Sendable (String?) -> Void)
}

public protocol SystemIntegrating: Sendable {
    func status() async throws -> SystemSetupStatus
    func configure(_ request: SystemRegistrationRequest) async throws
    func acquireListeners() async throws -> ListeningSockets
    func releaseListeners() async
    func removeSetup() async throws
}

public enum InstallationCertificate {
    public static func decodePEM(_ data: Data) throws -> Data {
        guard data.count < 16_384, let pem = String(data: data, encoding: .utf8) else {
            throw JerdError.invalid("The Jerd CA certificate is invalid.")
        }
        let begin = "-----BEGIN CERTIFICATE-----"
        let end = "-----END CERTIFICATE-----"
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(begin), trimmed.hasSuffix(end),
              let der = Data(base64Encoded: trimmed.dropFirst(begin.count).dropLast(end.count).filter { !$0.isWhitespace }) else {
            throw JerdError.invalid("The Jerd CA certificate is not valid PEM.")
        }
        return der
    }

    public static func fingerprint(_ der: Data) -> String { SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined() }

    public static func validate(_ der: Data, installationID: UUID) throws -> SecCertificate {
        guard der.count < 16_384, let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw JerdError.invalid("The Jerd CA certificate is invalid.")
        }
        var commonName: CFString?
        guard SecCertificateCopyCommonName(certificate, &commonName) == errSecSuccess,
              commonName as String? == "Jerd Local CA \(installationID.uuidString)",
              SecCertificateCopyNormalizedIssuerSequence(certificate) == SecCertificateCopyNormalizedSubjectSequence(certificate) else {
            throw JerdError.invalid("Only this installation's Jerd root CA can be trusted.")
        }
        let values = SecCertificateCopyValues(certificate, [kSecOIDBasicConstraints] as CFArray, nil) as? [String: Any]
        let constraint = values?[kSecOIDBasicConstraints as String] as? [String: Any]
        let properties = constraint?[kSecPropertyKeyValue as String] as? [[String: Any]]
        // Security.framework exposes the non-localized Basic Constraints label.
        guard properties?.contains(where: {
            ($0[kSecPropertyKeyLabel as String] as? String) == "Certificate Authority" &&
            (($0[kSecPropertyKeyValue as String] as? String) == "Yes" ||
             ($0[kSecPropertyKeyValue as String] as? NSNumber)?.boolValue == true)
        }) == true else { throw JerdError.invalid("The certificate is not a certificate authority.") }
        return certificate
    }
}
