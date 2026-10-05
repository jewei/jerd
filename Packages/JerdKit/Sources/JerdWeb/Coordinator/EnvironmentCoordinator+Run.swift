import Foundation
import JerdFoundation
import JerdProcess

extension EnvironmentCoordinator {
    /// Starts `plan` on the helper's listeners and checks every hostname through macOS trust.
    func startOwned(_ plan: ServingPlan, stamps: [String: ExecutableStamp], ticket: StopTicket) async throws {
        state = .starting
        guard let installationID = try InstallationIdentity(environment: environment).read() else {
            throw JerdError.unavailable("Select Enable HTTPS to approve setup for all enabled sites.")
        }
        // The helper owns 80 and 443 while it leases them; this check names another app that
        // listens there before the lease (spec B 7.1.13: the only port check, right before use).
        try await ports.requireNoListener(80)
        try await ports.requireNoListener(443)
        let leased = try await system.acquireListeners()
        listeners = leased
        try checkpoint(ticket)
        let layout = RunLayout.product(
            environment: environment, installationID: installationID, temporaryRoot: temporaryRoot)
        let engine = engine
        let start = Task { try await engine.start(plan, layout: layout, binding: .product, listeners: leased) }
        startup = start
        defer { startup = nil }
        let runID = try await start.value
        try await checkTrust(plan.hostnames)
        try checkpoint(ticket)
        guard await engine.state == .running else {
            throw JerdError.processFailed("The environment stopped during the HTTPS check.")
        }
        active = ActiveRun(plan: plan, stamps: stamps, runID: runID)
        state = .running
        monitor = Task { [weak self] in
            guard let failure = await engine.waitForFailure(of: runID) else { return }
            await self?.engineFailed(runID, failure)
        }
    }

    /// Checks all hostnames in parallel (spec B 7.1.14); the first failure ends the check.
    private func checkTrust(_ hostnames: [String]) async throws {
        let probe = probe
        try await withThrowingTaskGroup(of: Void.self) { group in
            for hostname in hostnames.sorted() { group.addTask { try await probe.check(hostname: hostname) } }
            try await group.waitForAll()
        }
    }

    /// Stops the engine and returns the listeners. The state is left to the caller.
    func cleanup() async {
        monitor?.cancel()
        monitor = nil
        await engine.stop()
        if let leased = listeners {
            try? leased.http.close()
            try? leased.https.close()
            listeners = nil
            await system.releaseListeners()
        }
        active = nil
    }

    /// A runtime of the current run exited: the run ends as failed, unless an operation owns it.
    private func engineFailed(_ runID: EngineRunID, _ failure: String) async {
        guard active?.runID == runID, gate.tryEnter() else { return }
        defer { gate.leave() }
        await cleanup()
        state = .failed(failure)
    }
}
