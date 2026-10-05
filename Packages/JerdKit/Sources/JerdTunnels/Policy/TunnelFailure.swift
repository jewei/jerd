import JerdFoundation

/// A failed launch, with the rule that decides whether a later attempt can cure it.
package struct TunnelFailure: Equatable, Sendable {
    package let error: JerdError
    /// True when a later launch can pass: a timeout, or a `TunnelRetryableError` from the connector.
    ///
    /// Every other failure needs the user, so a retry would only hide the cause: a missing or
    /// invalid token, a runtime mismatch, a lock of another session, an occupied port, a live
    /// earlier process, and every process failure without the marker (for example a missing
    /// executable, a process log that cannot be opened, or a connector that did not stop).
    package let isTransient: Bool

    package init(_ error: JerdError, isTransient: Bool) {
        self.error = error
        self.isTransient = isTransient
    }

    /// Wraps any error. Cancellation becomes "The tunnel operation was cancelled."
    package init(_ error: any Error) {
        switch error {
        case is CancellationError:
            self.init(.unavailable(TunnelMessage.cancelled), isTransient: false)
        case let retryable as TunnelRetryableError:
            self.init(retryable.error, isTransient: true)
        case let error as JerdError:
            self.init(error, isTransient: error.kind == .timedOut)
        default:
            self.init(.processFailed(FailureDetail.describe(error)), isTransient: false)
        }
    }

    package var message: String { error.message }
}
