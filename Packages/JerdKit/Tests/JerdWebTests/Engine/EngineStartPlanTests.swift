import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct EngineStartPlanTests {
    let layout = RunLayout(
        environment: DataLayout(root: URL(fileURLWithPath: "/data")).environment,
        socketDirectory: URL(fileURLWithPath: "/tmp/jerd-run"), authority: .installation(Certificates.installationID))

    func plan() throws -> EngineStartPlan {
        let first = Samples.runtime(id: Samples.runtimeID)
        let second = Samples.runtime(fpm: "/other/php-fpm")
        let sites = [
            PlannedSite(site: Samples.site(URL(fileURLWithPath: "/p/b"), hostname: "b.test"), runtime: first),
            PlannedSite(site: Samples.site(URL(fileURLWithPath: "/p/a"), hostname: "a.test"), runtime: second),
            PlannedSite(site: Samples.site(URL(fileURLWithPath: "/p/c"), hostname: "c.test"), runtime: first),
        ]
        let serving = ServingPlan(sites: sites, caddy: Samples.caddy())
        return try EngineStartPlan(
            plan: serving, validatedSites: sites.map(\.site), layout: layout, binding: .product)
    }

    @Test func eachDistinctRuntimeGetsOnePoolInPlanOrder() throws {
        let plan = try plan()
        #expect(plan.pools.map(\.runtime.fpmPath) == ["/local/php-fpm", "/other/php-fpm"])
        #expect(plan.pools.map(\.layout.socket.lastPathComponent) == ["php-0.sock", "php-1.sock"])
        #expect(plan.caddySites.map(\.socket.lastPathComponent) == ["php-0.sock", "php-1.sock", "php-0.sock"])
    }

    @Test func theCommandsHaveExactArgumentsAndTheRunEnvironment() throws {
        let plan = try plan()
        let pool = plan.pools[0].layout
        #expect(
            plan.fpmTest(plan.pools[0]).arguments == [
                "-c", pool.phpINIFile.path, "-y", pool.fpmConfigurationFile.path, "-t",
            ])
        #expect(plan.fpmLaunch(plan.pools[0]).arguments.last == "-F")
        #expect(plan.fpmLaunch(plan.pools[0]).environment == layout.processEnvironment)
        #expect(plan.fpmLaunch(plan.pools[0]).workingDirectory == layout.environment.root)
        #expect(plan.caddyLaunch(nil).arguments == ["run", "--config", "/data/environment/configuration/caddy.json"])
        #expect(plan.caddyValidation(nil).arguments.first == "validate")
    }

    @Test func theReadinessRequestVerifiesWithTheRunCAAndNeverSkipsVerification() throws {
        let request = try plan().readinessRequest(try Hostname("a.test"), maximumTime: 2)
        #expect(request.executable.path == "/usr/bin/curl")
        #expect(!request.arguments.contains("-k") && !request.arguments.contains("--insecure"))
        #expect(
            request.arguments == [
                "--noproxy", "*", "--silent", "--show-error", "--fail", "--max-time", "2",
                "--cacert", layout.rootCertificateFile.path, "--resolve", "a.test:443:127.0.0.1",
                "https://a.test:443/.jerd/ready",
            ])
    }
}
