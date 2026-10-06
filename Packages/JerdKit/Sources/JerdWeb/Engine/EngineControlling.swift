import Foundation
import JerdProcess

/// The handle of one engine run, for failure reports that belong to that run only.
public struct EngineRunID: Hashable, Sendable {
    let value = UUID()
}

/// Runs the unprivileged web processes. The coordinator depends on this role so tests can use a fake.
public protocol EngineControlling: Sendable {
    var state: EnvironmentState { get async }
    /// Validates a plan in a throwaway layout: no listener, no socket, no trust.
    func preflight(_ plan: ServingPlan, layout: RunLayout) async throws
    /// Starts every pool and Caddy, and returns when HTTPS answers for every site.
    func start(
        _ plan: ServingPlan, layout: RunLayout, binding: ListenerBinding, listeners: InheritedListeners?
    ) async throws -> EngineRunID
    /// Makes a running start stop at its next checkpoint. It does not wait.
    func requestStop() async
    /// Stops the run and waits until every owned process stopped. Afterwards `state` is
    /// `.stopped`, or `.failed` when a process is still running: then the run, its records, and
    /// its lock stay, a new start is refused, and the next stop retries.
    func stop() async
    /// True when the run is up and every pool answers its ping.
    func isHealthy() async -> Bool
    /// Waits until `run` fails (the message) or stops normally (nil).
    func waitForFailure(of run: EngineRunID) async -> String?
}
