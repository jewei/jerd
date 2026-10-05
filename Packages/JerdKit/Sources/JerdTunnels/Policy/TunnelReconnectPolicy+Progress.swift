extension TunnelReconnectPolicy {
    /// Applies a result of the current generation.
    func advance(
        _ lifecycle: inout TunnelLifecycle, _ progress: TunnelProgress, now: ContinuousClock.Instant
    ) -> TunnelStep {
        switch progress {
        case .launched:
            lifecycle.hasLaunched = true
            lifecycle.state = lifecycle.waitingState
            return .check(after: .zero)
        case .launchFailed(let failure):
            // The first launch reports every failure to the user. Later launches retry only
            // failures that time can cure (spec E 7.1.2).
            guard lifecycle.hasLaunched, failure.isTransient else { return lifecycle.fail(failure.message) }
            return retry(&lifecycle)
        case .probed(let probe):
            return probed(&lifecycle, probe, now: now)
        case .reaped(let reap):
            return reaped(&lifecycle, reap)
        case .disconnected(let reason, let stopError):
            return lifecycle.fail(reason.message(stopError: stopError))
        }
    }

    private func probed(
        _ lifecycle: inout TunnelLifecycle, _ probe: TunnelProbe, now: ContinuousClock.Instant
    ) -> TunnelStep {
        switch probe {
        case .ready:
            lifecycle.state = .connected
            lifecycle.hasConnected = true
            if let since = lifecycle.connectedSince {
                if since.duration(to: now) >= stableConnection { lifecycle.retries = 0 }
            } else {
                lifecycle.connectedSince = now
            }
            return .check(after: checkInterval)
        case .waiting:
            lifecycle.state = lifecycle.waitingState
            lifecycle.connectedSince = nil
            return .check(after: checkInterval)
        case .exited:
            return .reap
        case .tokenRejected:
            return beginFatal(&lifecycle, .tokenRejected)
        case .unexpectedListener:
            return beginFatal(&lifecycle, .unexpectedListener)
        }
    }

    private func reaped(_ lifecycle: inout TunnelLifecycle, _ reap: TunnelReap) -> TunnelStep {
        switch reap {
        case .notStopped(let message):
            return lifecycle.fail(message)
        case .stoppedAfterTokenRejection:
            return lifecycle.fail(TunnelFatalReason.tokenRejected.message(stopError: nil))
        case .stopped:
            guard lifecycle.restartOnFailure else { return lifecycle.fail(TunnelMessage.processExited) }
            return retry(&lifecycle)
        }
    }

    /// Shows the problem now, and keeps the generation until the graceful stop reports back.
    private func beginFatal(_ lifecycle: inout TunnelLifecycle, _ reason: TunnelFatalReason) -> TunnelStep {
        lifecycle.state = .failed(reason.message(stopError: nil))
        lifecycle.connectedSince = nil
        return .disconnect(reason)
    }

    private func retry(_ lifecycle: inout TunnelLifecycle) -> TunnelStep {
        let delay = retryDelay(after: lifecycle.retries)
        lifecycle.retries += 1
        lifecycle.connectedSince = nil
        lifecycle.state = lifecycle.waitingState
        return .relaunch(after: delay)
    }
}
