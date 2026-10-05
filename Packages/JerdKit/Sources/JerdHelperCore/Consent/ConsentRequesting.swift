import JerdSystem

/// Asks the app, over the reverse XPC interface, to apply or remove admin trust.
protocol ConsentRequesting: Sendable {
    /// Returns the app's `OSStatus`. Throws `.approvalInterrupted` when the app connection fails.
    func change(_ request: TrustConsentRequest) async throws -> Int32
}
