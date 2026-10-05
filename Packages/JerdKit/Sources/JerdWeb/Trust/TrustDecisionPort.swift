import Foundation

/// Tells whether macOS trusts a CA certificate for server TLS. Tests inject the answer.
public protocol TrustDecisionPort: Sendable {
    /// True when the saved user or admin trust settings of `der` pass `TrustDecision.accepts`.
    func isTrustedForServerTLS(_ der: Data) throws -> Bool
}
