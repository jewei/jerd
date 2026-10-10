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
    let forwardedHosts: any ForwardedHostsLoading
    /// One change at a time. A site change refuses at once when the gate is busy; a forwarded
    /// host apply waits for it (`waitingExclusive`).
    let gate = OperationGate()
    /// The current phase. Tests read it; the app shows the result of a change instead.
    package private(set) var phase: SiteChangePhase = .idle
    /// Every phase of the last change, in order, for tests.
    package private(set) var trace: [SiteChangePhase] = []
    /// The `.test` hostname of each site that the run served when the last change ended, by site
    /// ID. Readers use it instead of the run itself, which serves no site during a restart.
    package private(set) var servedHostnames: [UUID: String] = [:]

    /// - Parameter forwardedHosts: The saved public hostnames that the sites restore from a forwarder.
    package init(
        registry: SiteRegistry, reducer: SiteChangeReducer = SiteChangeReducer(),
        coordinator: any EnvironmentCoordinating, gateway: any SystemSetupManaging,
        forwardedHosts: any ForwardedHostsLoading
    ) {
        self.registry = registry
        self.reducer = reducer
        self.coordinator = coordinator
        self.gateway = gateway
        self.forwardedHosts = forwardedHosts
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
        servedHostnames = [:]
    }

    /// Moves to `next` and records it. The only place that changes the phase.
    func advance(to next: SiteChangePhase) {
        phase = next
        trace.append(next)
    }

    /// Runs one change, or refuses at once while another one runs.
    private func exclusive<Result: Sendable>(_ body: (StopTicket) async throws -> Result) async throws -> Result {
        guard gate.tryEnter() else { throw JerdError.unavailable("Wait for the current site edit.") }
        return try await holding(body)
    }

    /// Waits for the current change, then runs one change.
    func waitingExclusive<Result: Sendable>(_ body: (StopTicket) async throws -> Result) async throws -> Result {
        await gate.enter()
        return try await holding(body)
    }

    /// Runs `body` while the gate is held, records what the run serves, then opens the gate. The
    /// stop ticket is taken before the first step, so a Stop at any later moment ends the change.
    private func holding<Result: Sendable>(_ body: (StopTicket) async throws -> Result) async throws -> Result {
        trace = []
        let ticket = await coordinator.ticket()
        do {
            let result = try await body(ticket)
            await end()
            return result
        } catch {
            await end()
            throw error
        }
    }

    /// The end of every change, also a failed one.
    private func end() async {
        let sites = await coordinator.runningPlan()?.sites.map(\.site) ?? []
        // A plan has each site once; the merge only keeps a duplicate from trapping.
        servedHostnames = Dictionary(sites.map { ($0.id, $0.hostname) }) { first, _ in first }
        phase = .idle
        gate.leave()
    }
}
