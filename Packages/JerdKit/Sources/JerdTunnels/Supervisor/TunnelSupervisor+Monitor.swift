import Foundation
import JerdFoundation
import JerdProcess

extension TunnelSupervisor {
    /// Runs the steps that the reducer chooses until the generation ends or the task is cancelled.
    /// Each result goes back through the reducer, so a stale result changes nothing.
    func drive(_ id: UUID, _ generation: TunnelGeneration, from first: TunnelStep) async {
        var step = first
        while !Task.isCancelled {
            let progress: TunnelProgress
            switch step {
            case .idle:
                return
            case .launch:
                progress = await launch(id, generation)
            case .check(let delay):
                guard await pause(delay) else { return }
                progress = .probed(await probe(id))
            case .relaunch(let delay):
                guard await pause(delay) else { return }
                progress = await launch(id, generation)
            case .reap:
                progress = .reaped(await reap(id))
            case .disconnect(let reason):
                progress = .disconnected(reason, stopError: await disconnectOwned(id))
            }
            step = apply(.progress(generation, progress), to: id)
        }
    }

    /// Reads and checks the token, then launches a connector. Any process that the connector
    /// still owns after a failure stays tracked, so Stop can reach it.
    func launch(_ id: UUID, _ generation: TunnelGeneration) async -> TunnelProgress {
        var token: TunnelToken?
        do {
            guard isCurrent(generation, id), let registration = configuration.registration(id),
                let runtime = configuration.runtime
            else { throw CancellationError() }
            guard let text = try await secrets.read(id: id) else {
                throw JerdError.unavailable(TunnelMessage.tokenMissing)
            }
            token = try TunnelToken(text)
            guard let token, isCurrent(generation, id), !Task.isCancelled else { throw CancellationError() }
            handles[id] = try await connector.connect(
                TunnelLaunch(runtime: runtime, registration: registration, token: token))
            return .launched
        } catch {
            if let owned = await connector.ownedHandle(for: id) { handles[id] = owned }
            return .launchFailed(Self.redacted(TunnelFailure(error), token: token))
        }
    }

    /// One readiness check. The output of the current run is checked for a token rejection first.
    func probe(_ id: UUID) async -> TunnelProbe {
        guard let handle = handles[id] else { return .exited }
        let alive = await connector.isRunning(handle)
        if await outputRejectsToken(id) { return .tokenRejected }
        guard alive else { return .exited }
        do {
            switch try await connector.readiness(of: handle) {
            case .ready: return .ready
            case .waiting: return .waiting
            case .unexpectedListener: return .unexpectedListener
            }
        } catch {
            // The metrics endpoint can be absent during startup, or the network can be down.
            // Jerd never calls the public address to decide this.
            return .waiting
        }
    }

    /// Collects a connector that exited, then reads its last output again (a late log flush).
    func reap(_ id: UUID) async -> TunnelReap {
        if let message = await disconnectOwned(id) { return .notStopped(message) }
        return await outputRejectsToken(id) ? .stoppedAfterTokenRejection : .stopped
    }

    /// Stops the owned connector gracefully. Returns the error message when it still runs.
    func disconnectOwned(_ id: UUID) async -> String? {
        guard let handle = handles[id] else { return nil }
        do {
            try await connector.disconnect(handle)
            if handles[id] == handle { handles[id] = nil }
            return nil
        } catch {
            return FailureDetail.describe(error)
        }
    }

    private func outputRejectsToken(_ id: UUID) async -> Bool {
        do {
            return TunnelAuthFailureClassifier.rejectsToken(try await connector.currentOutput(for: id))
        } catch {
            // An unreadable log proves nothing about the token; the readiness check still runs.
            return false
        }
    }

    /// Waits on the injected clock. False when the task was cancelled.
    private func pause(_ delay: Duration) async -> Bool {
        guard delay > .zero else { return !Task.isCancelled }
        do {
            try await clock.sleep(for: delay)
            return true
        } catch {
            return false
        }
    }

    /// Replaces the token and its secret in a failure message with the redaction marker.
    private static func redacted(_ failure: TunnelFailure, token: TunnelToken?) -> TunnelFailure {
        guard let token else { return failure }
        let message = LogRedactor.redact(failure.message, values: token.redactedValues)
        return TunnelFailure(JerdError(failure.error.kind, message))
    }
}
