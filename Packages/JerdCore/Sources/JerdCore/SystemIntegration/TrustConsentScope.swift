import Foundation

/// The GUI must opt in to each transaction. Reverse XPC cannot request trust
/// for a different CA or hostname, or ask for consent while no setup is active.
public struct TrustConsentScope: Sendable {
    private let certificateDER: Data
    private let hostnames: Set<String>
    private let allowRemoval: Bool
    private let policies: Set<CertificateTrustPolicy>
    public init(certificateDER: Data, hostnames: Set<String>, allowRemoval: Bool,
                policies: Set<CertificateTrustPolicy> = [.hostnames]) {
        self.certificateDER = certificateDER; self.hostnames = hostnames; self.allowRemoval = allowRemoval
        self.policies = policies
    }
    public func allows(_ change: TrustConsentRequest) -> Bool {
        guard change.certificateDER == certificateDER else { return false }
        if let requested = change.hostnames {
            guard policies.contains(change.policy), !requested.isEmpty, Set(requested).count == requested.count else { return false }
            return Set(requested).isSubset(of: hostnames)
        }
        return allowRemoval
    }
}
