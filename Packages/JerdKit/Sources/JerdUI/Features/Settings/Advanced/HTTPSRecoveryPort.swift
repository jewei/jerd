import JerdSystem

/// The recovery of an interrupted HTTPS setup. JerdLive implements it with `HelperClient`.
public protocol HTTPSRecoveryPort: Sendable {
    /// The interrupted transaction that the helper reports, or nil when there is none or the
    /// helper is not registered.
    func pendingRecovery() async throws -> SystemRecoveryStatus?
    /// Runs the approved recovery. macOS can ask for administrator approval.
    func recover(_ status: SystemRecoveryStatus, action: SystemRecoveryAction) async throws
}
