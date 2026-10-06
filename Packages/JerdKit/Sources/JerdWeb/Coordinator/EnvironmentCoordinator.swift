import Foundation
import JerdFoundation
import JerdProcess

/// Runs the web environment for the approved sites: preflight, keep or replace a run, and stop.
///
/// One operation runs at a time (`OperationGate`). A Stop raises the stop epoch: every operation
/// with an older `StopTicket` ends with `CancellationError` at its next step, and the startup task
/// is cancelled. The coordinator never restarts an earlier plan; the transaction decides that.
///
/// An engine failure that arrives while an operation holds the gate waits in `pendingFailure`.
/// The operation applies it before it leaves the gate, so no failure is lost (review web-r1 H1).
public actor EnvironmentCoordinator: EnvironmentCoordinating {
    /// The served state of a successful run.
    struct ActiveRun {
        let plan: ServingPlan
        let stamps: [String: ExecutableStamp]
        let runID: EngineRunID
    }

    /// A runtime exit of `runID` that the monitor reported while the gate was busy.
    struct PendingFailure: Equatable {
        let runID: EngineRunID
        let message: String
    }

    let environment: EnvironmentLayout
    let system: any SystemSetupPort
    let engine: any EngineControlling
    let probe: any TrustProbing
    let ports: LoopbackPortGuard
    let startGate: StartGate
    let temporaryRoot: URL
    let id = UUID()
    let gate = OperationGate()
    var state: EnvironmentState = .stopped
    var stopEpoch: UInt64 = 0
    var active: ActiveRun?
    var listeners: InheritedListeners?
    var startup: Task<EngineRunID, any Error>?
    var monitor: Task<Void, Never>?
    var consumedTokens: Set<UUID> = []
    var pendingFailure: PendingFailure?

    public init(
        layout: DataLayout, system: any SystemSetupPort, engine: any EngineControlling = EngineRunner(),
        probe: any TrustProbing = SystemTrustProbe(), ports: LoopbackPortGuard = LoopbackPortGuard(),
        startGate: StartGate = StartGate(), temporaryRoot: URL = FileManager.default.temporaryDirectory
    ) {
        environment = layout.environment
        self.system = system
        self.engine = engine
        self.probe = probe
        self.ports = ports
        self.startGate = startGate
        self.temporaryRoot = temporaryRoot
    }

    public func snapshot() -> EnvironmentSnapshot {
        EnvironmentSnapshot(state: state, siteIDs: active?.plan.siteIDs ?? [])
    }

    public func runningPlan() -> ServingPlan? { active?.plan }

    public func ticket() -> StopTicket { StopTicket(epoch: stopEpoch) }

    public func isStopRequested(since ticket: StopTicket) -> Bool { ticket.epoch != stopEpoch }

    public func requestStop() async {
        stopEpoch &+= 1
        startup?.cancel()
        await engine.requestStop()
    }

    public func stop() async {
        await requestStop()
        await halt()
    }

    public func halt() async {
        await gate.enter()
        defer { gate.leave() }
        await cleanup()
        state = .stopped
    }

    public func markSetupRemoved() async {
        await halt()
        state = .setupRequired
    }

    /// Throws `CancellationError` when the task was cancelled or a Stop arrived after `ticket`.
    func checkpoint(_ ticket: StopTicket) throws {
        try Task.checkCancellation()
        guard !isStopRequested(since: ticket) else { throw CancellationError() }
    }

    /// Runs `body` as the one operation, or refuses at once when another one runs. A failure that
    /// the monitor reported meanwhile ends the run before the gate opens again. No suspension
    /// point lies between that check and `leave()`, so a later report finds the gate free.
    func operation<Value: Sendable>(_ body: () async throws -> Value) async throws -> Value {
        guard gate.tryEnter() else { throw JerdError.unavailable("Wait for the current environment operation.") }
        defer { gate.leave() }
        let result: Result<Value, any Error>
        do {
            result = .success(try await body())
        } catch {
            result = .failure(error)
        }
        await applyPendingFailure()
        return try result.get()
    }
}
