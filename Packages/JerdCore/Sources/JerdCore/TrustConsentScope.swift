import Foundation

/// The GUI must opt in to each transaction. Reverse XPC cannot request trust
/// for a different CA or hostname, or ask for consent while no setup is active.
public struct TrustConsentScope: Sendable {
    private let certificateDER: Data
    private let hostnames: Set<String>
    private let allowRemoval: Bool
    public init(certificateDER: Data, hostnames: Set<String>, allowRemoval: Bool) {
        self.certificateDER = certificateDER; self.hostnames = hostnames; self.allowRemoval = allowRemoval
    }
    public func allows(_ change: TrustConsentRequest) -> Bool {
        guard change.certificateDER == certificateDER else { return false }
        if let requested = change.hostnames {
            guard !requested.isEmpty, Set(requested).count == requested.count else { return false }
            return Set(requested).isSubset(of: hostnames)
        }
        return allowRemoval
    }
}
