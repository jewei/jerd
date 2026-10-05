import Foundation

/// A prepared approval: what the approval sheet shows and what the helper receives after approval.
public struct HTTPSSetup: Identifiable, Equatable, Sendable {
    public let registration: HTTPSRegistration

    public init(registration: HTTPSRegistration) {
        self.registration = registration
    }

    public var id: UUID { registration.installationID }
    public var hostnames: [String] { registration.hostnames }
    /// The CA fingerprint that the user compares in the macOS trust prompt.
    public var fingerprint: String { LocalCertificateAuthority.fingerprint(of: registration.certificateDER) }
}
