import Foundation
import JerdFoundation
import JerdProcess

@testable import JerdWeb

/// An engine that runs nothing. It counts starts and preflights and can fail or crash.
actor FakeEngine: EngineControlling {
    private(set) var state: EnvironmentState = .stopped
    private(set) var starts = 0
    private(set) var preflights = 0
    private(set) var stops = 0
    private(set) var startedSiteIDs: Set<UUID> = []
    private var failNextStart = false
    private var run: EngineRunID?
    private var ended: (run: EngineRunID, failure: String?)?
    private var waiters: [CheckedContinuation<String?, Never>] = []
    /// Runs inside `preflight`, for example to touch an executable.
    var onPreflight: @Sendable () throws -> Void = {}
    /// True while `preflight` or `isHealthy` waits for `resumeHeld()`.
    private(set) var isHolding = false
    private var holdPreflight = false
    private var holdHealthCheck = false
    private var heldWaiter: CheckedContinuation<Void, Never>?

    func rejectNextStart() { failNextStart = true }
    func setOnPreflight(_ action: @escaping @Sendable () throws -> Void) { onPreflight = action }
    /// The next `preflight` waits inside the engine until `resumeHeld()`.
    func holdNextPreflight() { holdPreflight = true }
    /// The next `isHealthy` decides "healthy" now, then waits until `resumeHeld()`.
    func holdNextHealthCheck() { holdHealthCheck = true }

    func resumeHeld() {
        heldWaiter?.resume()
        heldWaiter = nil
    }

    func preflight(_ plan: ServingPlan, layout: RunLayout) async throws {
        preflights += 1
        try OwnedDirectory.create(layout.environment.root)
        if holdPreflight {
            holdPreflight = false
            await hold()
        }
        try onPreflight()
    }

    func start(
        _ plan: ServingPlan, layout: RunLayout, binding: ListenerBinding, listeners: InheritedListeners?
    ) throws -> EngineRunID {
        try Task.checkCancellation()
        starts += 1
        if failNextStart {
            failNextStart = false
            state = .failed("Injected startup failure")
            throw JerdError.processFailed("Injected startup failure")
        }
        startedSiteIDs = plan.siteIDs
        state = .running
        let id = EngineRunID()
        run = id
        return id
    }

    func requestStop() {}

    func stop() {
        stops += 1
        state = .stopped
        finish(nil)
    }

    func isHealthy() async -> Bool {
        let healthy = state == .running
        if holdHealthCheck {
            holdHealthCheck = false
            await hold()
        }
        return healthy
    }

    private func hold() async {
        isHolding = true
        await withCheckedContinuation { heldWaiter = $0 }
        isHolding = false
    }

    func waitForFailure(of run: EngineRunID) async -> String? {
        if let ended, ended.run == run { return ended.failure }
        guard self.run == run, state == .running else { return nil }
        return await withCheckedContinuation { waiters.append($0) }
    }

    /// A runtime exit: the run fails with `message`.
    func crash(_ message: String = "test exit") {
        state = .failed(message)
        finish(message)
    }

    private func finish(_ failure: String?) {
        if let run { ended = (run, failure) }
        run = nil
        for waiter in waiters { waiter.resume(returning: failure) }
        waiters.removeAll()
    }
}
