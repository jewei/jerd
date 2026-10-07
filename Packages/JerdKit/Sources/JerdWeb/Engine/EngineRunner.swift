import Darwin
import Foundation
import JerdFoundation
import JerdProcess

/// The serving engine: it starts, checks, watches, and stops Caddy and one PHP-FPM master per
/// runtime, all unprivileged. System trust is the coordinator's job.
///
/// One operation runs at a time (`OperationGate`). A stop request raises the stop epoch, and a
/// running start throws `CancellationError` at its next checkpoint, so no request is lost.
public actor EngineRunner: EngineControlling {
    /// The message when a watched process exits during a run.
    public static let exitMessage = "An owned runtime exited. The environment was stopped. See the run logs."

    public internal(set) var state: EnvironmentState = .stopped
    let services: EngineServices
    let gate = OperationGate()
    var run: ActiveRun?
    var stopEpoch: UInt64 = 0
    let monitor = EngineMonitor()
    /// The end of the last run: its ID and the failure message (nil after a normal stop).
    var lastOutcome: (run: EngineRunID, failure: String?)?
    var failureWaiters: [EngineRunID: [CheckedContinuation<String?, Never>]] = [:]

    public init(services: EngineServices = EngineServices()) {
        self.services = services
    }

    public func requestStop() {
        stopEpoch &+= 1
    }

    public func stop() async {
        stopEpoch &+= 1
        await gate.enter()
        defer { gate.leave() }
        state = Self.stoppedState(failure: nil, survivor: await stopOwned())
    }

    public func isHealthy() async -> Bool {
        guard !gate.isBusy, state == .running, let run, await allRunning(run) else { return false }
        let pinger = services.pinger
        let healthy = await withTaskGroup(of: Bool.self) { group in
            for pool in run.pools {
                group.addTask { (try? await pinger.ping(socket: pool.socket)) != nil }
            }
            return await group.allSatisfy { $0 }
        }
        return healthy && !gate.isBusy && state == .running
    }

    public func waitForFailure(of runID: EngineRunID) async -> String? {
        if let lastOutcome, lastOutcome.run == runID { return lastOutcome.failure }
        guard run?.id == runID else { return nil }
        return await withCheckedContinuation { failureWaiters[runID, default: []].append($0) }
    }

    /// Throws `CancellationError` after a stop request or a task cancellation.
    func checkpoint(_ epoch: UInt64) throws {
        try Task.checkCancellation()
        guard stopEpoch == epoch else { throw CancellationError() }
    }

    func allRunning(_ run: ActiveRun) async -> Bool {
        guard run.caddy != nil, !run.pools.isEmpty else { return false }
        for token in run.started where await services.processes.state(of: token) != .running { return false }
        return true
    }

    /// Ends a run: every waiter of it learns the outcome once.
    func finish(_ runID: EngineRunID, failure: String?) {
        lastOutcome = (runID, failure)
        for waiter in failureWaiters.removeValue(forKey: runID) ?? [] { waiter.resume(returning: failure) }
    }
}
