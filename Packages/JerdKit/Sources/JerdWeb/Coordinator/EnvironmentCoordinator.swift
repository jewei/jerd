import Foundation
import JerdFoundation
import JerdProcess

/// Runs the web environment for the approved sites: preflight, keep or replace a run, and stop.
///
/// One operation runs at a time (`OperationGate`). A Stop raises the stop epoch: every operation
/// with an older `StopTicket` ends with `CancellationError` at its next step, and the startup task
/// is cancelled. The coordinator never restarts an earlier plan; the transaction decides that.
public actor EnvironmentCoordinator: EnvironmentCoordinating {
    /// The served state of a successful run.
    struct ActiveRun {
        let plan: ServingPlan
        let stamps: [String: ExecutableStamp]
        let runID: EngineRunID
    }

    let environment: EnvironmentLayout
    let system: any SystemSetupPort
    let engine: any EngineControlling
    let probe: any TrustProbing
    let ports: LoopbackPortGuard
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

    public init(
        layout: DataLayout, system: any SystemSetupPort, engine: any EngineControlling = EngineRunner(),
        probe: any TrustProbing = SystemTrustProbe(), ports: LoopbackPortGuard = LoopbackPortGuard(),
        temporaryRoot: URL = FileManager.default.temporaryDirectory
    ) {
        environment = layout.environment
        self.system = system
        self.engine = engine
        self.probe = probe
        self.ports = ports
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

    /// Takes the gate for one operation, or refuses at once when another one runs.
    func enterOperation() throws {
        guard gate.tryEnter() else { throw JerdError.unavailable("Wait for the current environment operation.") }
    }
}
