import Foundation

/// The one rule for "these hostnames are approved" (spec B 7.3.9), used by the coordinator, the
/// site change transaction, and the app.
public enum ApprovalPredicate {
    /// True when the hosts section and the server-TLS trust are in place, no recovery is pending,
    /// and every hostname is approved.
    public static func covers(_ status: HTTPSSetupStatus, hostnames: some Sequence<String>) -> Bool {
        status.hostsConfigured && status.trustConfigured && status.trustPolicy == .serverTLS
            && !status.hasPendingRecovery && Set(hostnames).isSubset(of: Set(status.hostnames))
    }

    /// True when the approved CA is this installation's CA, by ID and fingerprint.
    public static func matches(_ status: HTTPSSetupStatus, installationID: UUID, fingerprint: String) -> Bool {
        status.installationID == installationID && status.certificateSHA256 == fingerprint
    }
}
