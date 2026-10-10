import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct PublicHostCoordinatorTests {
    @Test func aNewTunnelUpdatesARunningSiteAndAnUnchangedTunnelKeepsIt() async throws {
        let source = FakePublicHosts()
        let harness = try CoordinatorHarness(publicHosts: source)
        defer { harness.remove() }
        let site = try harness.site("demo.test")
        try await harness.ensure(harness.plan([site]))
        let host = try SitePublicHost(siteID: site.id, hostname: "public.example.com")
        await source.set([host])
        try await harness.coordinator.preparePublicHosts(for: site.id)
        #expect(await harness.engine.starts == 2)
        #expect(await harness.coordinator.runningPlan()?.publicHosts == [host])
        try await harness.coordinator.preparePublicHosts(for: site.id)
        #expect(await harness.engine.starts == 2)
        await source.set([])
        try await harness.ensure(harness.plan([site]))
        #expect(await harness.engine.starts == 3)
        #expect(await harness.coordinator.runningPlan()?.publicHosts.isEmpty == true)
        await harness.coordinator.stop()
    }

    @Test func unreadableRoutesKeepTheCurrentRunAndDoNotPreventStop() async throws {
        let source = FakePublicHosts()
        let harness = try CoordinatorHarness(publicHosts: source)
        defer { harness.remove() }
        let site = try harness.site("demo.test")
        try await harness.ensure(harness.plan([site]))
        await source.rejectReads()
        await #expect(throws: JerdError.self) { try await harness.coordinator.preparePublicHosts(for: site.id) }
        #expect(await harness.engine.starts == 1)
        #expect(await harness.coordinator.snapshot().state == .running)
        try await harness.ensure(harness.plan([]))
        #expect(await harness.coordinator.snapshot().state == .stopped)
    }

    @Test func aStoppedSiteCannotBeStartedByAConnector() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        await #expect(throws: JerdError.self) { try await harness.coordinator.preparePublicHosts(for: UUID()) }
        #expect(await harness.engine.starts == 0)
    }

    @Test func aChangedMappingCannotUseAPreflightTokenForTheOldMapping() async throws {
        let source = FakePublicHosts()
        let harness = try CoordinatorHarness(publicHosts: source)
        defer { harness.remove() }
        let site = try harness.site("demo.test")
        let plan = harness.plan([site])
        let prepared = try await harness.coordinator.preflight(plan, ticket: await harness.coordinator.ticket())
        let host = try SitePublicHost(siteID: site.id, hostname: "public.example.com")
        await source.set([host])
        try await harness.ensure(plan, prepared: prepared)
        #expect(await harness.engine.preflights == 2)
        #expect(await harness.coordinator.runningPlan()?.publicHosts == [host])
        await harness.coordinator.stop()
    }
}
