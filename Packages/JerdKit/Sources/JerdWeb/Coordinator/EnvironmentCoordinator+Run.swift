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
        // A web process that survived a crash keeps 80 and 443, so the recovery message must come
        // before the port check (review final-domain-r1 M1). The engine checks again under the lock.
        try WebProcessRecords(environment: environment, gate: startGate, recorder: ActiveRunRecorder())
            .requireNoLivePrevious()
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
    /// - Returns: the engine failure when a web process is still running after the stop (its run,
    ///   records, and lock stay in the engine), or nil (review final-domain-r1 L1).
    @discardableResult
    func cleanup() async -> String? {
        monitor?.cancel()
        monitor = nil
        await engine.stop()
        var survivor: String?
        if case .failed(let message) = await engine.state { survivor = message }
        if let leased = listeners {
            try? leased.http.close()
            try? leased.https.close()
            listeners = nil
            await system.releaseListeners()
        }
        active = nil
        pendingFailure = nil
        return survivor
    }

    /// A runtime of the current run exited: the run ends as failed now, or, while an operation
    /// holds the gate, when that operation ends (`applyPendingFailure`).
    private func engineFailed(_ runID: EngineRunID, _ failure: String) async {
        guard active?.runID == runID else { return }
        guard gate.tryEnter() else {
            pendingFailure = PendingFailure(runID: runID, message: failure)
            return
        }
        defer { gate.leave() }
        state = EngineRunner.stoppedState(failure: failure, survivor: await cleanup())
    }

    /// Ends the run as failed when its failure arrived during the operation that ends now. A run
    /// that the operation already replaced or stopped is not affected.
    func applyPendingFailure() async {
        guard let failure = pendingFailure else { return }
        pendingFailure = nil
        guard active?.runID == failure.runID else { return }
        state = EngineRunner.stoppedState(failure: failure.message, survivor: await cleanup())
    }
}
