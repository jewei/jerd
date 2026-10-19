import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct EngineRunnerAliasTests {
    /// A start is ready only after verified HTTPS answers for the hostname and every alias.
    @Test func aStartChecksHTTPSForTheHostnameAndEveryAlias() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let base = try harness.plan()
        var site = base.sites[0].site
        site.aliases = ["api.demo.test"]
        let plan = ServingPlan(sites: [PlannedSite(site: site, runtime: base.sites[0].runtime)], caddy: base.caddy)
        _ = try await harness.start(plan, layout: try harness.layout())
        #expect(await harness.engine.state == .running)
        let checked = Set(
            harness.commands.arguments.compactMap { arguments in
                arguments.first { $0.hasPrefix("https://") }
            })
        #expect(checked.contains { $0.hasPrefix("https://demo.test") })
        #expect(checked.contains { $0.hasPrefix("https://api.demo.test") })
        await harness.engine.stop()
    }
}
