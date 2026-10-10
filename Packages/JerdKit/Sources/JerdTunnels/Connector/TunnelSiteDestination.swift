import Foundation

/// The current site hostname and the certificate authority that its HTTPS listener uses.
public struct TunnelSiteDestination: Equatable, Sendable {
    public let hostname: String
    public let certificateAuthority: URL

    public init(hostname: String, certificateAuthority: URL) {
        self.hostname = hostname
        self.certificateAuthority = certificateAuthority
    }
}
