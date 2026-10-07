import Foundation
import JerdFoundation

@testable import JerdWeb

/// A coordinator that keeps a plan in memory. Steps can fail or wait for a Stop.
actor FakeCoordinator: EnvironmentCoordinating {
    private(set) var running: ServingPlan?
    private(set) var preflights = 0
    private(set) var launches = 0
    private(set) var halts = 0
    private(set) var stops = 0
    private(set) var setupRemoved = false
    private(set) var isWaitingInPreflight = false
    private var epoch: UInt64 = 0
    private var failPreflight = false
    private var failActivations = 0
    private var holdPreflight = false
    private var preflightWaiter: CheckedContinuation<Void, Never>?

    init(_ plan: ServingPlan? = nil) {
        running = plan
    }

    /// The next `count` activations of a changed plan fail; the run is then stopped.
    func failActivations(_ count: Int) { failActivations = count }
    func failNextPreflight() { failPreflight = true }
    func holdNextPreflight() { holdPreflight = true }

    func snapshot() -> EnvironmentSnapshot {
        EnvironmentSnapshot(state: running == nil ? .stopped : .running, siteIDs: running?.siteIDs ?? [])
    }

    func runningPlan() -> ServingPlan? { running }
    func ticket() -> StopTicket { StopTicket(epoch: epoch) }
    func isStopRequested(since ticket: StopTicket) -> Bool { ticket.epoch != epoch }

    func preflight(_ plan: ServingPlan, ticket: StopTicket) async throws -> PreparedPlan {
        preflights += 1
        if holdPreflight {
            holdPreflight = false
            isWaitingInPreflight = true
            await withCheckedContinuation { preflightWaiter = $0 }
            isWaitingInPreflight = false
        }
        guard !isStopRequested(since: ticket) else { throw CancellationError() }
        if failPreflight {
            failPreflight = false
            throw JerdError.invalid("Test invalid runtime")
        }
        return PreparedPlan(id: UUID(), issuer: UUID(), plan: plan, stamps: [:])
    }

    func ensure(_ plan: ServingPlan, prepared: PreparedPlan?, ticket: StopTicket) throws {
        guard !isStopRequested(since: ticket) else { throw CancellationError() }
        guard !plan.isEmpty else {
            running = nil
            return
        }
        if let running, running.isEquivalent(to: plan) { return }
        launches += 1
        if failActivations > 0 {
            failActivations -= 1
            running = nil
            throw JerdError.processFailed("Test failed launch")
        }
        running = plan
    }

    func halt() {
        halts += 1
        running = nil
    }

    func markSetupRemoved() {
        running = nil
        setupRemoved = true
    }

    func requestStop() {
        epoch &+= 1
        preflightWaiter?.resume()
        preflightWaiter = nil
    }

    func stop() {
        stops += 1
        requestStop()
        running = nil
    }
}
