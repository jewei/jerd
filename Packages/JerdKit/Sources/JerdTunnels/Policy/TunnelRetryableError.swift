import Foundation
import JerdFoundation

/// A launch failure that the connector marks as curable by a later try, for example a connector
/// that exited before Jerd could check its identity. The supervisor classifies by this type, not
/// by message text, and shows only `error`.
package struct TunnelRetryableError: Error, LocalizedError, Equatable, Sendable {
    package let error: JerdError

    package init(_ error: JerdError) { self.error = error }

    package var errorDescription: String? { error.message }
}
