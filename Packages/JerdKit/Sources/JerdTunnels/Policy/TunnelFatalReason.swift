/// A problem that ends the current generation and needs the user.
package enum TunnelFatalReason: Equatable, Sendable {
    case tokenRejected
    case unexpectedListener

    /// The state message, given the result of the graceful stop that follows the problem.
    package func message(stopError: String?) -> String {
        switch self {
        case .tokenRejected:
            stopError.map { TunnelMessage.tokenRejectedPrefix + $0 } ?? TunnelMessage.tokenRejected
        case .unexpectedListener:
            // A failed stop keeps the connector owned, so an explicit Stop can retry it.
            TunnelMessage.unexpectedListener
        }
    }
}
