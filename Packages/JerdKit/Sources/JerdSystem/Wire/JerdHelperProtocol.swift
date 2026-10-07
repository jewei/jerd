import Foundation

/// The XPC interface that the helper exports and the app calls.
///
/// The Objective-C selectors and the reply block types are a compatibility contract between an
/// installed helper and a newer or older app. `HelperWireProtocol.helperSelectors` lists them, and a
/// snapshot test pins their type encodings. Do not rename a method or change a parameter type.
@objc public protocol JerdHelperProtocol {
    /// Replies with JSON `SystemSetupStatus`, or with an error text.
    func status(reply: @escaping @Sendable (Data?, String?) -> Void)
    /// Applies a JSON `SystemRegistrationRequest`. A nil error text means success.
    func configureSite(_ request: Data, reply: @escaping @Sendable (String?) -> Void)
    /// Replies with the HTTP and HTTPS listeners on ports 80 and 443, or with an error text.
    func acquireListeners(reply: @escaping @Sendable (FileHandle?, FileHandle?, String?) -> Void)
    /// Releases the listeners when this connection holds them.
    func releaseListeners(reply: @escaping @Sendable () -> Void)
    /// Removes the hosts section, the CA, and the registration. A nil error text means success.
    func removeSetup(reply: @escaping @Sendable (String?) -> Void)
    /// Runs an approved recovery from a JSON `SystemRecoveryApproval`. A nil error text means success.
    func recoverSetup(_ approval: Data, reply: @escaping @Sendable (String?) -> Void)
}
