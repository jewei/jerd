import Foundation
import JerdFoundation
import JerdProcess

extension EngineRunner {
    /// Validates `plan` in `layout`, a throwaway tree: the sites, the runtimes against their
    /// records, every pool file with `php-fpm -t`, and the Caddy JSON with `caddy validate` on the
    /// fixed preflight ports. It opens no listener, creates no socket, and changes no trust.
    /// The caller deletes the tree.
    public func preflight(_ plan: ServingPlan, layout: RunLayout) async throws {
        guard !plan.isEmpty else { return }
        let sites = try SiteValidator().revalidate(plan.sites.map(\.site))
        let startPlan = try EngineStartPlan(plan: plan, validatedSites: sites, layout: layout, binding: .preflight)
        try EngineFiles.createFolders(startPlan)
        try await requireUnchanged(startPlan)
        for pool in startPlan.pools {
            try Task.checkCancellation()
            try EngineFiles.writePool(pool, caBundle: nil)
            try await validate(startPlan.fpmTest(pool))
        }
        try Task.checkCancellation()
        try EngineFiles.writeCaddy(startPlan)
        try await validate(startPlan.caddyValidation(nil))
    }
}
