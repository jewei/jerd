import Darwin
import Foundation
import JerdFoundation
import JerdProcess

extension EngineRunner {
    /// The failure text when Caddy or a PHP-FPM master is still running after its forceful stop.
    static let survivorMessage =
        "PHP-FPM or Caddy did not stop. Jerd kept its process record and the environment lock. Select Stop again."

    /// Caddy stops with SIGTERM and PHP-FPM with SIGQUIT (graceful worker finish), each with
    /// the bounded forceful policy: Caddy and FPM hold no user data.
    static func stopPolicy(for token: ProcessToken, in run: ActiveRun) -> StopPolicy {
        .forceful(signal: token == run.caddy ? SIGTERM : SIGQUIT)
    }

    /// Stops everything the current run owns, in reverse start order, and forgets the run.
    ///
    /// A record is deleted only when its process is proven gone; otherwise it stays for process
    /// recovery. The socket folder is removed only when this run created it.
    ///
    /// When a process is still running after its stop (`timedOut`), the run, its lock, its
    /// records, and its socket folder stay, and the survivor message is returned. A later stop
    /// retries; a new start is refused until then. The stop of the web processes stays forceful,
    /// because they hold no user data. Quit goes on after the web stage and does not wait: the
    /// kept record makes the next launch name process recovery.
    @discardableResult
    func stopOwned(failure: String? = nil) async -> String? {
        await monitor.cancel()
        guard let current = run else { return nil }
        var survived = false
        for token in current.stopOrder {
            let outcome = await services.processes.stop(token, policy: Self.stopPolicy(for: token, in: current))
            if case .timedOut = outcome { survived = true }
        }
        // Waiters learn the end of this run now, also when a process survived.
        guard !survived else {
            finish(current.id, failure: failure)
            return Self.survivorMessage
        }
        if let lock = current.lock {
            let records = records(current.layout)
            for token in current.started { _ = records.remove(token, holding: lock) }
            lock.release()
        }
        if current.ownsSocketDirectory {
            // Only stale sockets of this run remain; a failed removal leaves a private empty folder.
            try? FileManager.default.removeItem(at: current.layout.socketDirectory)
        }
        // The run ends only now, so a waiter that asks during the stop learns the outcome.
        run = nil
        finish(current.id, failure: failure)
        return nil
    }

    /// The state after a stop that ended with `failure`: the failure, the survivor message, or both.
    static func stoppedState(failure: String?, survivor: String?) -> EnvironmentState {
        let parts = [failure, survivor].compactMap { $0 }
        return parts.isEmpty ? .stopped : .failed(parts.joined(separator: " "))
    }
}
