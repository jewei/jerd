import Darwin
import Foundation
import JerdFoundation
import JerdProcess

/// The checks between a launch and "running": the FPM socket, the FPM ping, verified HTTPS for
/// every site, and listener ownership.
struct ReadinessChecks: Sendable {
    /// Throws `CancellationError` when the start must stop.
    typealias Checkpoint = @Sendable () async throws -> Void
    /// True while every launched service still runs.
    typealias Liveness = @Sendable () async -> Bool

    let commands: any CommandRunning
    let pinger: any FPMPinging
    let ports: LoopbackPortGuard
    let timings: ReadinessTimings

    /// Waits until `socket` is a Unix socket while FPM keeps running.
    func waitForSocket(_ socket: URL, running: Liveness, checkpoint: Checkpoint) async throws {
        let deadline = ContinuousClock.now + timings.socketWait
        while ContinuousClock.now < deadline {
            try await checkpoint()
            guard await running() else {
                throw JerdError.processFailed("PHP-FPM exited before its socket was ready. See fpm.log.")
            }
            var info = stat()
            if lstat(socket.path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK { return }
            try await Task.sleep(for: timings.socketPoll)
        }
        throw JerdError.processFailed("PHP-FPM did not create its socket. See fpm.log.")
    }

    /// Checks verified HTTPS for every site in parallel, within one budget for all of them
    /// (spec B 7.1.14). The first failure cancels the other checks.
    func waitForHTTPS(
        _ plan: EngineStartPlan, running: @escaping Liveness, checkpoint: @escaping Checkpoint
    ) async throws {
        let deadline = ContinuousClock.now + timings.tlsBudget
        try await withThrowingTaskGroup(of: Void.self) { group in
            for site in plan.caddySites {
                group.addTask {
                    try await waitForHTTPS(
                        site.hostname, plan, deadline: deadline, running: running, checkpoint: checkpoint)
                }
            }
            try await group.waitForAll()
        }
    }

    private func waitForHTTPS(
        _ hostname: Hostname, _ plan: EngineStartPlan, deadline: ContinuousClock.Instant, running: Liveness,
        checkpoint: Checkpoint
    ) async throws {
        var detail = "No certificate is available."
        // At least one attempt runs, also when the budget passed during the other checks.
        repeat {
            try await checkpoint()
            guard await running() else {
                throw JerdError.processFailed("A runtime exited during startup. See the run logs.")
            }
            if FileProbe.presence(at: plan.layout.rootCertificateFile) != .absent {
                let request = plan.readinessRequest(hostname, maximumTime: timings.requestSeconds)
                let result = try await commands.run(request, timeout: timings.requestTimeout)
                if result.succeeded, result.output == SiteRoutePolicy.healthResponse { return }
                detail = result.diagnosticOutput
            }
            try await Task.sleep(for: timings.tlsPoll)
        } while ContinuousClock.now < deadline
        throw JerdError.processFailed("TLS readiness failed: \(detail)")
    }

    /// Caddy listens only on the expected loopback ports and has no UDP socket; with its own
    /// ports it must also be their only listener. PHP-FPM has no TCP listener.
    func verifyListeners(caddy: pid_t?, fpm: [pid_t?], binding: ListenerBinding) async throws {
        guard let caddy else { throw JerdError.processFailed("Caddy exited before listener checks.") }
        try await ports.verifyOwnership(
            pid: caddy, expected: [binding.httpsPort, binding.httpPort], requireExclusive: !binding.inherited)
        for pid in fpm {
            guard let pid else { throw JerdError.processFailed("PHP-FPM exited before listener checks.") }
            try await ports.verifyOwnership(pid: pid, expected: [], requireExclusive: false, allowUDP: true)
        }
    }
}
