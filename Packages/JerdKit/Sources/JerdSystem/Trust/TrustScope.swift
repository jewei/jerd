/// The macOS trust settings that a policy produces: one unrestricted SSL server rule, or one
/// SSL rule per hostname. Only the hostname form needs hostnames.
public enum TrustScope: Hashable, Sendable {
    case serverTLS
    case hostnames(ValidatedHostnames)

    public init(policy: CertificateTrustPolicy, hostnames: ValidatedHostnames) {
        switch policy {
        case .serverTLS: self = .serverTLS
        case .hostnames: self = .hostnames(hostnames)
        }
    }

    public var policy: CertificateTrustPolicy {
        switch self {
        case .serverTLS: .serverTLS
        case .hostnames: .hostnames
        }
    }
}
