import JerdFoundation

/// A failed launch, with the rule that decides whether a later attempt can cure it.
package struct TunnelFailure: Equatable, Sendable {
    package let error: JerdError

    package init(_ error: JerdError) { self.error = error }

    /// Wraps any error. Cancellation becomes "The tunnel operation was cancelled."
    package init(_ error: any Error) {
        if error is CancellationError {
            self.error = .unavailable(TunnelMessage.cancelled)
        } else if let error = error as? JerdError {
            self.error = error
        } else {
            self.error = .processFailed(FailureDetail.describe(error))
        }
    }

    package var message: String { error.message }

    /// Only a timeout or a process that could not start or exited early can pass on a later try.
    /// A missing or invalid token, a runtime mismatch, a lock of another session, an occupied port,
    /// or a live earlier process needs the user, so retrying would only hide the cause.
    package var isTransient: Bool {
        error.kind == .timedOut || error.kind == .processFailed
    }
}
