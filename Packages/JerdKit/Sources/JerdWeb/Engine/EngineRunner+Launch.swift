import Darwin
import Foundation
import JerdFoundation
import JerdProcess

extension EngineRunner {
    /// Starts each pool and waits for its socket and ping, then starts Caddy.
    func launch(_ plan: EngineStartPlan, listeners: InheritedListeners?, epoch: UInt64) async throws {
        let readiness = services.readiness
        let processes = services.processes
        for pool in plan.pools {
            try checkpoint(epoch)
            let token = try await spawn(
                plan.fpmLaunch(pool), log: pool.layout.logFile, label: "PHP \(pool.runtime.version)", signal: SIGQUIT,
                plan: plan)
            run?.pools.append((token, pool.layout.socket))
            try checkpoint(epoch)
            try await readiness.waitForSocket(
                pool.layout.socket, running: { await processes.state(of: token) == .running },
                checkpoint: { try await self.checkpoint(epoch) })
            try await services.pinger.ping(socket: pool.layout.socket)
        }
        try checkpoint(epoch)
        let caddy = try await spawn(
            plan.caddyLaunch(listeners), log: plan.layout.environment.caddyLogFile,
            label: "Caddy \(plan.caddy.version)",
            signal: SIGTERM, plan: plan)
        run?.caddy = caddy
        try checkpoint(epoch)
    }

    /// Waits for verified HTTPS and checks the listeners, then marks the run as running.
    func confirm(_ plan: EngineStartPlan, epoch: UInt64) async throws -> EngineRunID {
        guard let current = run, let caddy = current.caddy else { throw CancellationError() }
        let readiness = services.readiness
        try await readiness.waitForHTTPS(
            plan, running: { await self.isComplete() }, checkpoint: { try await self.checkpoint(epoch) })
        let processes = services.processes
        var fpm: [pid_t?] = []
        for pool in current.pools { fpm.append(await processes.processID(of: pool.token)) }
        try await readiness.verifyListeners(
            caddy: await processes.processID(of: caddy), fpm: fpm, binding: plan.binding)
        try checkpoint(epoch)
        state = .running
        let runID = current.id
        await monitor.watch(current.started, processes: processes) { await self.runtimeExited(runID) }
        return runID
    }

    /// Starts one process and saves its run record while the environment lock is held.
    private func spawn(
        _ request: ProcessRequest, log: URL, label: String, signal: Int32, plan: EngineStartPlan
    ) async throws -> ProcessToken {
        let token = try await services.processes.start(request, log: ProcessLogFile(url: log))
        run?.started.append(token)
        guard let lock = run?.lock else { throw CancellationError() }
        if let pid = await services.processes.processID(of: token) {
            try records(plan.layout).record(token, pid: pid, label: label, signal: signal, holding: lock)
        }
        return token
    }

    private func isComplete() async -> Bool {
        guard let run else { return false }
        return await allRunning(run)
    }

    /// The monitor's report: the run fails once and every process stops.
    private func runtimeExited(_ runID: EngineRunID) async {
        guard run?.id == runID, gate.tryEnter() else { return }
        defer { gate.leave() }
        state = .failed(Self.exitMessage)
        let survivor = await stopOwned(failure: Self.exitMessage)
        state = Self.stoppedState(failure: Self.exitMessage, survivor: survivor)
    }
}
