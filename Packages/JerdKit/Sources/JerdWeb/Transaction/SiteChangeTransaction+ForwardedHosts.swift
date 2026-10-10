import Foundation
import JerdFoundation

extension SiteChangeTransaction {
    /// Applies the saved forwarded hosts to the run before a forwarder sends traffic to `siteID`,
    /// and returns that site as the run serves it, or nil when the run does not serve it.
    ///
    /// It waits for the current site change, so it never fails because an edit runs and never cuts
    /// into one. Only a changed mapping restarts the run, and a failed restart restores the previous
    /// run once. The restart runs in its own task: a tunnel Stop cancels the caller, and that must
    /// not stop every site halfway.
    /// - Throws: When the saved routes cannot be read, or when the restart fails.
    package func applyForwardedHosts(servingSite siteID: UUID) async throws -> Site? {
        try await waitingExclusive { ticket in
            try Task.checkCancellation()
            guard let running = await coordinator.runningPlan(),
                let served = running.sites.first(where: { $0.site.id == siteID })?.site
            else { return nil }
            let plan = running.forwarding(try await forwardedHosts.loadForwardedHosts())
            guard plan.forwardedHosts != running.forwardedHosts else { return served }
            // A Stop of the forwarder during the reads must not start a restart of every site.
            try Task.checkCancellation()
            try await Task { try await self.restart(running, as: plan, ticket: ticket) }.value
            return served
        }
    }

    /// Replaces the run with `plan` through the commit, so a failure rolls back as for a site change.
    private func restart(_ running: ServingPlan, as plan: ServingPlan, ticket: StopTicket) async throws {
        let configuration = try await registry.snapshot()
        let status = try await gateway.status()
        guard !status.hasPendingRecovery else {
            throw JerdError.unavailable("Recover the interrupted HTTPS setup in Advanced before connecting.")
        }
        let request = SiteChangeRequest(
            previous: configuration, candidate: configuration, selection: .exactly(running.siteIDs))
        let context = Context(
            request: request, ticket: ticket, running: running, plan: plan, status: status, prepared: nil,
            approved: nil)
        _ = try await commit(context)
    }
}
