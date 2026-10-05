import Foundation
import JerdFoundation
import JerdProcess

extension EnvironmentCoordinator {
    public func preflight(_ plan: ServingPlan, ticket: StopTicket) async throws -> PreparedPlan {
        try enterOperation()
        defer { gate.leave() }
        try checkpoint(ticket)
        let stamps = try ExecutableStamp.capture(plan.executablePaths)
        try await preflightOwned(plan)
        guard try ExecutableStamp.capture(plan.executablePaths) == stamps else {
            throw JerdError.unavailable("A runtime changed during preparation. Retry the change.")
        }
        return PreparedPlan(id: UUID(), issuer: id, plan: plan, stamps: stamps)
    }

    public func ensure(_ plan: ServingPlan, prepared: PreparedPlan?, ticket: StopTicket) async throws {
        try enterOperation()
        defer { gate.leave() }
        try checkpoint(ticket)
        guard !plan.isEmpty else {
            await cleanup()
            state = .stopped
            return
        }
        let stamps = try ExecutableStamp.capture(plan.executablePaths)
        try await requireApproval(of: plan)
        if let active, active.plan.isEquivalent(to: plan), active.stamps == stamps, await engine.isHealthy() {
            return
        }
        if !accept(prepared, for: plan, stamps: stamps) { try await preflightOwned(plan) }
        try checkpoint(ticket)
        await cleanup()
        do {
            try await startOwned(plan, stamps: stamps, ticket: ticket)
        } catch {
            await cleanup()
            state = error is CancellationError ? .stopped : .failed(FailureDetail.describe(error))
            throw error
        }
    }

    /// Every hostname must be approved with server TLS, and the approved CA must be this
    /// installation's CA. Otherwise nothing stops: the active sites keep running.
    private func requireApproval(of plan: ServingPlan) async throws {
        let status = try await system.status()
        guard ApprovalPredicate.covers(status, hostnames: plan.hostnames) else {
            throw JerdError.unavailable("Approve HTTPS setup for the changed sites before activation.")
        }
        guard let installationID = try InstallationIdentity(environment: environment).read(),
            ApprovalPredicate.matches(
                status, installationID: installationID,
                fingerprint: try LocalCertificateAuthority.read(environment.rootCertificateFile).fingerprint)
        else {
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
