import Foundation
import JerdFoundation
import JerdProcess

extension EnvironmentCoordinator {
    public func preflight(_ plan: ServingPlan, ticket: StopTicket) async throws -> PreparedPlan {
        try await operation {
            try checkpoint(ticket)
            let plan = try await resolvePublicHosts(plan)
            try checkpoint(ticket)
            let stamps = try ExecutableStamp.capture(plan.executablePaths)
            try await preflightOwned(plan)
            try checkpoint(ticket)
            guard try ExecutableStamp.capture(plan.executablePaths) == stamps else {
                throw JerdError.unavailable("A runtime changed during preparation. Retry the change.")
            }
            return PreparedPlan(id: UUID(), issuer: id, plan: plan, stamps: stamps)
        }
    }

    public func ensure(_ plan: ServingPlan, prepared: PreparedPlan?, ticket: StopTicket) async throws {
        try await operation {
            try checkpoint(ticket)
            guard !plan.isEmpty else {
                state = EngineRunner.stoppedState(failure: nil, survivor: await cleanup())
                return
            }
            let plan = try await resolvePublicHosts(plan)
            try checkpoint(ticket)
            let stamps = try ExecutableStamp.capture(plan.executablePaths)
            // A kept run activates nothing new, so it needs no approval check. This lets a
            // rollback keep the previous run that a refused activation never stopped.
            if await keeps(plan, stamps: stamps) { return }
            try await requireApproval(of: plan)
            if !accept(prepared, for: plan, stamps: stamps) { try await preflightOwned(plan) }
            try checkpoint(ticket)
            if let survivor = await cleanup() {
                state = .failed(survivor)
                throw JerdError.processFailed(survivor)
            }
            do {
                try await startOwned(plan, stamps: stamps, ticket: ticket)
            } catch {
                let failure = error is CancellationError ? nil : FailureDetail.describe(error)
                state = EngineRunner.stoppedState(failure: failure, survivor: await cleanup())
                throw error
            }
        }
    }

    /// Rechecks tunnel registrations before comparing plans, so a new route replaces the web run.
    private func resolvePublicHosts(_ plan: ServingPlan) async throws -> ServingPlan {
        guard !plan.isEmpty, let publicHosts else { return plan }
        return try await ServingPlan(sites: plan.sites, caddy: plan.caddy, publicHosts: publicHosts.loadPublicHosts())
    }

    /// True when the active run serves an equivalent plan with the same executables and is
    /// healthy. A run with a reported failure is never kept.
    private func keeps(_ plan: ServingPlan, stamps: [String: ExecutableStamp]) async -> Bool {
        guard let active, pendingFailure?.runID != active.runID, active.plan.isEquivalent(to: plan),
            active.stamps == stamps
        else { return false }
        return await engine.isHealthy()
    }

    /// Every hostname must be approved with server TLS, and the approved CA must be this
    /// installation's CA. Otherwise nothing stops: the active sites keep running.
    private func requireApproval(of plan: ServingPlan) async throws {
        let status = try await system.status()
        guard ApprovalPredicate.covers(status, hostnames: plan.hostnames) else {
            throw JerdError.unavailable("Approve HTTPS setup for the changed sites before activation.")
        }
        let authority = try InstallationAuthority.read(environment)
        guard ApprovalPredicate.approves(status, hostnames: plan.hostnames, authority: authority) else {
            throw JerdError.unavailable(
                "The local CA does not match the approved HTTPS setup. The active sites were kept running.")
        }
    }

    /// A token passes once, when this coordinator issued it, for an equivalent plan, with equal stamps.
    private func accept(_ prepared: PreparedPlan?, for plan: ServingPlan, stamps: [String: ExecutableStamp]) -> Bool {
        guard let prepared, prepared.issuer == id, !consumedTokens.contains(prepared.id),
            prepared.stamps == stamps, prepared.plan.isEquivalent(to: plan)
        else { return false }
        consumedTokens.insert(prepared.id)
        return true
    }

    /// Runs the engine preflight in `environment/preflight-<UUID>/` and deletes the tree after.
    private func preflightOwned(_ plan: ServingPlan) async throws {
        let layout = RunLayout.preflight(within: environment, temporaryRoot: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: layout.preflightTree) }
        try await engine.preflight(plan, layout: layout)
    }
}
