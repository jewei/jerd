import Darwin
import Foundation
import JerdFoundation
import JerdProcess

/// One managed service instance: one data folder, one lock, at most one owned server process,
/// and the explicit `ServiceState` machine.
///
/// Rules:
/// - A start runs the shared safety steps in a fixed order (see `ServiceDefinition`).
/// - A stop is graceful and never sends `SIGKILL`. A timeout gives `stuck`: the process, its
///   lock, and its run record stay, and only a later Stop can clear it.
/// - A stale run record is removed only while the lock is held.
/// - Exit detection (`refresh()`) never waits for a stop. A user Stop joins a running exit stop,
///   so it is never blocked by "busy".
/// - A maintenance lease (runtime update) keeps the lock for the whole operation.
public actor ManagedInstance {
    /// Who asked for the stop that is in progress. It decides the state after the stop.
    enum StopIntent: Sendable {
        /// A Stop by the user or a lease. Success gives `stopped`.
        case user
        /// Exit detection. Success gives `failed` with the exit reason.
        case exit(reason: String)
        /// A step inside a start. The start failure path sets the state.
        case startStep
    }

    struct PendingStop {
        let token: ProcessToken
        let task: Task<StopResult, Never>
    }

    public internal(set) var state: ServiceState = .stopped
    public internal(set) var definition: any ServiceDefinition
    let effects: ServiceEffects
    var lock: InstanceLock?
    var process: OwnedServiceProcess?
    var pendingStop: PendingStop?
    var stopIntent: StopIntent = .startStep
    var lease: UUID?

    public init(definition: any ServiceDefinition, effects: ServiceEffects) {
        self.definition = definition
        self.effects = effects
    }

    /// The PID of the owned process, also while it is stuck.
    public var processID: pid_t? { process?.processID }

    /// True while this instance holds its data lock.
    public var holdsLock: Bool { lock?.isHeld ?? false }

    /// Replaces the definition, for example after a port change. Only without a process.
    public func replaceDefinition(_ next: any ServiceDefinition) throws {
        try requireNoLease()
        guard process == nil, !state.isBusy else { throw JerdError.unavailable(messages.busy) }
        definition = next
    }

    /// Waits until a stop that is in progress has finished, for example one that exit detection began.
    package func waitForPendingStop() async {
        if let pendingStop { _ = await pendingStop.task.value }
    }

    var messages: ServiceMessages { definition.profile.messages }

    /// Applies an event through the one transition rule. An invalid event keeps the state.
    func apply(_ event: ServiceEvent) {
        if let next = state.applying(event) { state = next }
    }

    func requireNoLease() throws {
        guard lease == nil else { throw JerdError.unavailable(messages.busy) }
    }

    /// Releases the lock when no process and no lease need it.
    func releaseLockIfIdle() {
        guard process == nil, lease == nil else { return }
        lock?.release()
        lock = nil
    }

    /// The redacted end of the server log of `owned`.
    func logTail(_ owned: OwnedServiceProcess) -> String {
        definition.profile.log.tail(redacting: owned.plan.secrets, fallback: messages.logUnavailable)
    }
}
