import Foundation
import JerdFoundation

extension SiteChangeTransaction {
    /// The facts that the commit and the rollback need.
    struct Context: Sendable {
        let request: SiteChangeRequest
        let ticket: StopTicket
        let running: ServingPlan?
        let plan: ServingPlan?
        let status: HTTPSSetupStatus
        let prepared: PreparedPlan?
        let approved: HTTPSSetup?
    }

    /// S0 to S4. Any failure here changes nothing and is reported as it is.
    func perform(
        _ request: SiteChangeRequest, ticket: StopTicket, approved: HTTPSSetup?, prepared: PreparedPlan?
    ) async throws -> SiteChangeResult {
        if case .keepRunning = request.selection, request.candidate == request.previous {
            advance(to: .noChange)
            return .committed(request.previous)
        }
        advance(to: .planning)
        let running = await coordinator.runningPlan()
        let plan = try Self.plan(for: request, running: running)?.forwarding(
            await savedForwardedHosts(keeping: running))
        advance(to: .recoveryGate)
        let status = try await gateway.status()
        guard !status.hasPendingRecovery else {
            throw JerdError.unavailable("Recover the interrupted HTTPS setup in Advanced before changing sites.")
        }
        advance(to: .preparing)
        let token = try await prepare(plan, running: running, reusing: prepared, ticket: ticket)
        // The full rule, the CA included: a regenerated or missing CA leads to
        // an approval, whose `prepare` creates or loads the CA, instead of a failed activation.
        if let plan, approved == nil,
            !ApprovalPredicate.approves(
                status, hostnames: plan.hostnames, authority: try await gateway.localAuthority())
        {
            let setup = try await gateway.prepare(hostnames: request.registeredHostnames, caddy: plan.caddy)
            advance(to: .awaitingApproval)
            return .needsApproval(PendingSiteChange(setup: setup, request: request, prepared: token))
        }
        if let approved, Set(approved.hostnames) != Set(request.registeredHostnames) {
            throw JerdError.invalid("The approved hostnames do not match the edit.")
        }
        advance(to: .stopGate)
        guard await !coordinator.isStopRequested(since: ticket) else { throw CancellationError() }
        let context = Context(
            request: request, ticket: ticket, running: running, plan: plan, status: status, prepared: token,
            approved: approved)
        return .committed(try await commit(context))
    }

    /// S1: the sites to run after the change, or nil to run nothing.
    static func plan(for request: SiteChangeRequest, running: ServingPlan?) throws -> ServingPlan? {
        let enabled = Set(request.candidate.sites.filter(\.isEnabled).map(\.id))
        let selected: Set<UUID>
        switch request.selection {
        case .exactly(let ids):
            selected = ids.intersection(enabled)
        case .keepRunning(let startIfStopped):
            guard running != nil || startIfStopped else { return nil }
            let before = Set(request.previous.sites.filter(\.isEnabled).map(\.id))
            selected = (running?.siteIDs ?? []).union(enabled.subtracting(before)).intersection(enabled)
        }
        return selected.isEmpty ? nil : try ServingPlan(request.candidate, siteIDs: selected)
    }

    /// The saved forwarded hosts. Tunnel settings never block a site change: when they cannot be
    /// read, the hosts of the current run stay, and a Connect reports the read failure.
    func savedForwardedHosts(keeping running: ServingPlan?) async -> ForwardedHosts {
        do {
            return try await forwardedHosts.loadForwardedHosts()
        } catch {
            return running?.forwardedHosts ?? .none
        }
    }

    /// S3: a preflight only when the plan differs from the run, and none when an equivalent
    /// token from before the approval exists.
    private func prepare(
        _ plan: ServingPlan?, running: ServingPlan?, reusing token: PreparedPlan?, ticket: StopTicket
    ) async throws -> PreparedPlan? {
        guard let plan, running?.isEquivalent(to: plan) != true else { return nil }
        if let token, token.plan.isEquivalent(to: plan) { return token }
        return try await coordinator.preflight(plan, ticket: ticket)
    }
}
