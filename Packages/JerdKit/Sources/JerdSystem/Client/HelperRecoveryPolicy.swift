import JerdFoundation

/// What the app does after a call to the helper failed in transport. Pure, with a table test.
///
/// Rules: a lost connection is retried once on a new connection (launchd starts the helper on
/// demand, also after an idle helper exited). A signature mismatch means that the helper still
/// runs code from before an app update: the client restarts the helper once per app run through
/// the approved registration (no hosts or trust change), then retries once. It never restarts
/// while this app holds the listeners, because the sites still use the old helper's sockets. A
/// retry is never retried, so the recovery cannot loop.
enum HelperRecoveryPolicy {
    /// The state of the one automatic restart of a client.
    enum Restart: Equatable, Sendable {
        case available
        case running
        case used
    }

    /// The next step after the first failure of a call.
    enum Step: Equatable, Sendable {
        /// Open a new connection and send the call again.
        case retry
        /// Restart the helper, then send the call again.
        case restartThenRetry
        /// Wait for the restart that another call started, then send the call again.
        case awaitRestartThenRetry
        /// Show this error. The call is not sent again.
        case fail(JerdError)
    }

    static func step(after failure: HelperTransportError, restart: Restart, holdsListeners: Bool) -> Step {
        switch failure.cause {
        case .connectionLost:
            return .retry
        case .other:
            return .fail(failure.userError)
        case .signatureMismatch:
            if holdsListeners { return .fail(staleWhileServing(failure)) }
            switch restart {
            case .available: return .restartThenRetry
            case .running: return .awaitRestartThenRetry
            case .used: return .fail(staleAfterRestart(failure))
            }
        }
    }

    /// The error of the retry. A signature mismatch after the restart means that the helper file
    /// itself does not match this app.
    static func errorAfterRetry(_ failure: HelperTransportError) -> JerdError {
        failure.cause == .signatureMismatch ? staleAfterRestart(failure) : failure.userError
    }

    static func staleAfterRestart(_ failure: HelperTransportError) -> JerdError {
        JerdError.unavailable(
            "Jerd restarted its system helper, but the helper still does not match this copy of Jerd. Click "
                + "Reconnect Helper… to try again. If it fails again, install Jerd again from its disk image "
                + "into Applications. \(failure.reference)"
        ).with(.reconnectHelper)
    }

    static func staleWhileServing(_ failure: HelperTransportError) -> JerdError {
        JerdError.unavailable(
            "The Jerd system helper changed while sites ran. Stop all sites, then click Reconnect Helper…, or "
                + "choose it in the System Setup menu (the shield button in the Sites toolbar). "
                + failure.reference
        ).with(.reconnectHelper)
    }
}
