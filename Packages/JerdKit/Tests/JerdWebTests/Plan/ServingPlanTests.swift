import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct ServingPlanTests {
    @Test func aPlanKeepsEnabledSelectedSitesInSavedOrder() throws {
        let one = Samples.site(URL(fileURLWithPath: "/p/one"), hostname: "one.test")
        let two = Samples.site(URL(fileURLWithPath: "/p/two"), hostname: "two.test")
        let off = Samples.site(URL(fileURLWithPath: "/p/off"), hostname: "off.test", enabled: false)
        let configuration = Samples.configuration([two, off, one])
        #expect(try ServingPlan(configuration).hostnames == ["two.test", "one.test"])
        #expect(try ServingPlan(configuration, siteIDs: [one.id, off.id]).hostnames == ["one.test"])
        #expect(try ServingPlan(configuration, siteIDs: []).isEmpty)
    }

    @Test func aSelectedRunDoesNotResolveStoppedSitesRuntimes() throws {
        let active = Samples.site(URL(fileURLWithPath: "/p/a"), hostname: "a.test")
        let stopped = Samples.site(URL(fileURLWithPath: "/p/b"), hostname: "b.test", selection: .pinned(UUID()))
        let configuration = Samples.configuration([active, stopped])
        #expect(try ServingPlan(configuration, siteIDs: [active.id]).siteIDs == [active.id])
        #expect(throws: JerdError.self) { try ServingPlan(configuration) }
    }

    @Test func aMissingCaddyIsUnavailable() {
        var configuration = Samples.configuration([])
        configuration.caddy = nil
        #expect(throws: JerdError.unavailable("Caddy is unavailable.")) { try ServingPlan(configuration) }
    }

    @Test(arguments: PlanField.allCases)
    func equivalenceDependsOnlyOnServedFields(_ field: PlanField) throws {
        let site = Samples.site(URL(fileURLWithPath: "/p/a"), hostname: "a.test")
        let base = ServingPlan(
            sites: [PlannedSite(site: site, runtime: Samples.runtime(id: Samples.runtimeID))],
            caddy: Samples.caddy())
        #expect(base.isEquivalent(to: field.apply(to: base)) == !field.restarts)
        #expect(field.apply(to: base).isEquivalent(to: base) == !field.restarts)
    }

    @Test func siteOrderDoesNotChangeEquivalenceButCountDoes() {
        let one = PlannedSite(
            site: Samples.site(URL(fileURLWithPath: "/p/1"), hostname: "one.test"),
            runtime: Samples.runtime())
        let two = PlannedSite(
            site: Samples.site(URL(fileURLWithPath: "/p/2"), hostname: "two.test"),
            runtime: Samples.runtime())
        let plan = ServingPlan(sites: [one, two], caddy: Samples.caddy())
        #expect(plan.isEquivalent(to: ServingPlan(sites: [two, one], caddy: Samples.caddy())))
        #expect(!plan.isEquivalent(to: ServingPlan(sites: [one], caddy: Samples.caddy())))
    }

    @Test func forwardedHostsOfSitesOutsideThePlanAreDropped() {
        let planned = PlannedSite(site: Samples.site(URL(fileURLWithPath: "/p/1")), runtime: Samples.runtime())
        let host = PublicHostname("public.example.com")!
        let plan = ServingPlan(
            sites: [planned], caddy: Samples.caddy(),
            forwardedHosts: ForwardedHosts([planned.site.id: [host], UUID(): [host]]))
        #expect(plan.forwardedHosts == ForwardedHosts([planned.site.id: [host]]))
        #expect(
            plan.isEquivalent(to: ServingPlan(sites: [planned], caddy: Samples.caddy()).forwarding(plan.forwardedHosts))
        )
        #expect(
            ServingPlan(sites: [planned], caddy: Samples.caddy()).forwarding(ForwardedHosts([UUID(): [host]]))
                .forwardedHosts == .none)
    }

    @Test func executablePathsAreCaddyAndEachRuntimePair() {
        let site = PlannedSite(site: Samples.site(URL(fileURLWithPath: "/p/1")), runtime: Samples.runtime())
        #expect(
            ServingPlan(sites: [site], caddy: Samples.caddy()).executablePaths
                == ["/local/caddy", "/local/php", "/local/php-fpm"])
    }
}

/// One field change and whether it makes the plan different.
enum PlanField: CaseIterable, Sendable {
    case displayName, enabled, selection, inspectedAt
    case siteID, hostname, project, documentRoot
    case runtimeID, cliPath, fpmPath, version, architectures, cliExtensions, fpmExtensions
    case caddyPath, caddyVersion, caddyArchitectures
    case forwardedHost

    var restarts: Bool { ![.displayName, .enabled, .selection, .inspectedAt].contains(self) }

    func apply(to plan: ServingPlan) -> ServingPlan {
        var site = plan.sites[0].site
        let old = plan.sites[0].runtime
        var runtime = (
            id: old.id, cli: old.cliPath, fpm: old.fpmPath, version: old.version, architectures: old.architectures,
            cliExtensions: old.cliExtensions, fpmExtensions: old.fpmExtensions, inspectedAt: old.inspectedAt
        )
        var caddy = (path: plan.caddy.path, version: plan.caddy.version, architectures: plan.caddy.architectures)
        switch self {
        case .displayName: site.displayName = "Other"
        case .enabled: site.isEnabled.toggle()
        case .selection: site.phpSelection = .pinned(old.id)
        case .inspectedAt: runtime.inspectedAt = Date(timeIntervalSinceReferenceDate: 99)
        case .siteID: site.id = UUID()
        case .hostname: site.hostname = "z.test"
        case .project: site.projectPath = "/p"
        case .documentRoot: site.documentRoot = "/p/a/public"
        case .runtimeID: runtime.id = UUID()
        case .cliPath: runtime.cli = "/other/php"
        case .fpmPath: runtime.fpm = "/other/php-fpm"
        case .version: runtime.version = "9.0.0"
        case .architectures: runtime.architectures = [.arm64, .x86_64]
        case .cliExtensions: runtime.cliExtensions = ["Core"]
        case .fpmExtensions: runtime.fpmExtensions = ["Core"]
        case .caddyPath: caddy.path = "/other/caddy"
        case .caddyVersion: caddy.version = "v2.12.0"
        case .caddyArchitectures: caddy.architectures = [.arm64, .x86_64]
        case .forwardedHost: break
        }
        let changed = DevelopmentRuntime(
            id: runtime.id, cliPath: runtime.cli, fpmPath: runtime.fpm, version: runtime.version,
            architectures: runtime.architectures, cliExtensions: runtime.cliExtensions,
            fpmExtensions: runtime.fpmExtensions, inspectedAt: runtime.inspectedAt)
        let hosts = self == .forwardedHost ? ForwardedHosts([site.id: [PublicHostname("public.example.com")!]]) : .none
        return ServingPlan(
            sites: [PlannedSite(site: site, runtime: changed)],
            caddy: CaddyRuntime(path: caddy.path, version: caddy.version, architectures: caddy.architectures),
            forwardedHosts: hosts)
    }
}
