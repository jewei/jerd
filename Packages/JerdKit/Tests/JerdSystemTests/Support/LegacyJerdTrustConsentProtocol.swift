import Foundation

@testable import JerdSystem

/// A copy of the old `JerdCore.JerdTrustConsentProtocol` declaration.
@objc(LegacyJerdTrustConsentProtocol) protocol LegacyJerdTrustConsentProtocol {
    func changeTrust(_ request: Data, reply: @escaping @Sendable (Int32) -> Void)
}
