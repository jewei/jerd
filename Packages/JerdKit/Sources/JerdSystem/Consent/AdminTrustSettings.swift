import Foundation
import Security

/// The live admin trust settings of the logged-in user's Mac (Security.framework).
public struct AdminTrustSettings: TrustSettingsApplying {
    public init() {}

    public func setAdminTrust(certificateDER: Data, scope: TrustScope) -> OSStatus {
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            return errSecAuthFailed
        }
        return SecTrustSettingsSetTrustSettings(certificate, .admin, TrustSettingsPolicy.make(scope) as CFArray)
    }

    public func removeAdminTrust(certificateDER: Data) -> OSStatus {
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            return errSecAuthFailed
        }
        return SecTrustSettingsRemoveTrustSettings(certificate, .admin)
    }
}
