import Darwin
import Foundation
import JerdFoundation
import JerdProcess

extension EngineRunner {
    /// Caddy stops with SIGTERM and PHP-FPM with SIGQUIT (graceful worker finish), each with
    /// the bounded forceful policy: Caddy and FPM hold no user data.
    static func stopPolicy(for token: ProcessToken, in run: ActiveRun) -> StopPolicy {
        .forceful(signal: token == run.caddy ? SIGTERM : SIGQUIT)
    }

    /// Stops everything the current run owns, in reverse start order, and forgets the run.
    ///
    /// A record is deleted only when its process is proven gone; otherwise it stays for process
    /// recovery. The socket folder is removed only when this run created it.
    func stopOwned(failure: String? = nil) async {
        await monitor.cancel()
        guard let current = run else { return }
        for token in current.stopOrder {
            _ = await services.processes.stop(token, policy: Self.stopPolicy(for: token, in: current))
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
    }
}
