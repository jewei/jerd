import Foundation
import JerdFoundation

/// One site edit, Start, or Stop of sites as a transaction: plan, prepare, ask for approval when
/// needed, change the system setup, save, activate, and on failure roll back once.
///
/// It is the only owner of rollback: the coordinator never restarts a previous
/// run, so a failure restarts the previous run once and reports once. Every step carries the
/// `StopTicket` from the start, so a Stop during any step ends the change and prevents a restart.
public actor SiteChangeTransaction {
    let registry: SiteRegistry
    let reducer: SiteChangeReducer
    let coordinator: any EnvironmentCoordinating
    let gateway: any SystemSetupManaging
    private var busy = false
    /// The current phase. Tests read it; the app shows the result of a change instead.
    package private(set) var phase: SiteChangePhase = .idle
    /// Every phase of the last change, in order, for tests.
    package private(set) var trace: [SiteChangePhase] = []

    public init(
        registry: SiteRegistry, reducer: SiteChangeReducer = SiteChangeReducer(),
        coordinator: any EnvironmentCoordinating, gateway: any SystemSetupManaging
    ) {
        self.registry = registry
        self.reducer = reducer
        self.coordinator = coordinator
        self.gateway = gateway
    }

    /// Edits the configuration. Validation errors change nothing.
    public func apply(_ change: SiteChange, startIfStopped: Bool = false) async throws -> SiteChangeResult {
        try await exclusive { ticket in
            let previous = try await registry.snapshot()
            let candidate = try reducer.reduce(previous, change)
            let request = SiteChangeRequest(
                previous: previous, candidate: candidate, selection: .keepRunning(startIfStopped: startIfStopped))
            return try await perform(request, ticket: ticket, approved: nil, prepared: nil)
        }
    }

    /// Runs exactly `siteIDs` (Start or Stop of sites). The saved `isEnabled` does not change.
    public func run(_ siteIDs: Set<UUID>) async throws -> SiteChangeResult {
        try await exclusive { ticket in
            let current = try await registry.snapshot()
            let enabled = Set(current.sites.filter(\.isEnabled).map(\.id))
            guard siteIDs.isSubset(of: enabled) else {
                throw JerdError.invalid("The selected sites changed or are disabled. Select the sites again.")
            }
            let request = SiteChangeRequest(previous: current, candidate: current, selection: .exactly(siteIDs))
            return try await perform(request, ticket: ticket, approved: nil, prepared: nil)
        }
    }

    /// Continues a change after the user approved its HTTPS setup.
    public func approve(_ pending: PendingSiteChange) async throws -> AppConfiguration {
        try await exclusive { ticket in
            guard try await registry.snapshot() == pending.request.previous else {
                throw JerdError.unavailable("The site settings changed. Save and approve the edit again.")
            }
            let result = try await perform(
                pending.request, ticket: ticket, approved: pending.setup, prepared: pending.prepared)
            guard case .committed(let configuration) = result else {
                throw JerdError.invalid("The approved site edit could not be applied.")
            }
            return configuration
        }
    }

    /// The user's Stop: it ends the current change and every run step that began before it,
    /// prevents the change's rollback from restarting a run, and then stops the run.
    public func requestStop() async {
        await coordinator.stop()
    }

    /// Moves to `next` and records it. The only place that changes the phase.
    func advance(to next: SiteChangePhase) {
        phase = next
        trace.append(next)
    }

    /// Runs one change. Its stop ticket is taken before its first suspension, so a Stop at any
    /// later moment ends it.
    private func exclusive<Result: Sendable>(_ body: (StopTicket) async throws -> Result) async throws -> Result {
        guard !busy else { throw JerdError.unavailable("Wait for the current site edit.") }
        busy = true
        trace = []
        defer {
            busy = false
            phase = .idle
        }
        let ticket = await coordinator.ticket()
        return try await body(ticket)
    }
}
