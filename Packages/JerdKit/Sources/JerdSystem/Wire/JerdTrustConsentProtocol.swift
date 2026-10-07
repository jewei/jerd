import Foundation

/// The reverse XPC interface that the app exports on the same connection. The helper calls it to
/// set or remove admin trust, because only a GUI process can show the macOS authentication prompt.
///
/// The selector `changeTrust:reply:` and its types are a compatibility contract. Do not change them.
@objc public protocol JerdTrustConsentProtocol {
    /// Applies a JSON `TrustConsentRequest` and replies with an `OSStatus`.
    func changeTrust(_ request: Data, reply: @escaping @Sendable (Int32) -> Void)
}
