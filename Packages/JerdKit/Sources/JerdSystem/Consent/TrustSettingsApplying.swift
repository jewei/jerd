import Foundation

/// Sets or removes the admin-domain trust settings of a certificate. Only a GUI process can do
/// this, because macOS shows an authentication prompt. Calls block; run them off the main thread.
public protocol TrustSettingsApplying: Sendable {
    /// Applies the trust settings of `scope` to the certificate. Returns the Security status.
    func setAdminTrust(certificateDER: Data, scope: TrustScope) -> OSStatus
    /// Removes the admin trust settings of the certificate. Returns the Security status.
    func removeAdminTrust(certificateDER: Data) -> OSStatus
}
