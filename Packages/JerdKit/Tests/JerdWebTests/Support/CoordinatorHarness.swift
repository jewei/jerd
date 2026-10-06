import Foundation
import JerdFoundation
import JerdProcess

@testable import JerdWeb

/// A coordinator with a fake engine, helper, and probe, an installed fixture CA, and real
/// executables (copies of `/usr/bin/true`) so that stamps work.
struct CoordinatorHarness {
    let folder: TemporaryDirectory
    let layout: DataLayout
    let system: FakeSystem
    let engine = FakeEngine()
    let probe: FakeProbe
    let coordinator: EnvironmentCoordinator
    let binary: URL

    init(
        approved hostnames: [String] = ["demo.test"], policy: HTTPSTrustPolicy = .serverTLS, probeFails: Bool = false,
        portsOccupied: Bool = false
    )
        throws
    {
        folder = try TemporaryDirectory(" coordinator")
        layout = DataLayout(root: folder.url)
        try Certificates.install(in: layout.environment)
        binary = folder.path("binary")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: binary)
        system = FakeSystem(try FakeSystem.approved(hostnames, policy: policy))
        probe = FakeProbe(failing: probeFails)
        // `lsof` exits 1 when no process listens; with a listener it names one PID.
        let lsof = ScriptedCommandRunner { _ in
            portsOccupied ? CommandResult(status: 0, output: "p999\n") : CommandResult(status: 1, output: "")
        }
        coordinator = EnvironmentCoordinator(
            layout: layout, system: system, engine: engine, probe: probe,
            ports: LoopbackPortGuard(commands: lsof), temporaryRoot: URL(fileURLWithPath: "/tmp"))
    }

    var runtime: DevelopmentRuntime { Samples.runtime(id: Samples.runtimeID, cli: binary.path, fpm: binary.path) }
    var caddy: CaddyRuntime { Samples.caddy(path: binary.path) }

    /// A site in its own project folder.
    func site(_ hostname: String) throws -> Site {
        Samples.site(try folder.folder("projects/\(hostname)"), hostname: hostname)
    }

    func plan(_ sites: [Site]) -> ServingPlan {
        ServingPlan(sites: sites.map { PlannedSite(site: $0, runtime: runtime) }, caddy: caddy)
    }

    func ensure(_ plan: ServingPlan, prepared: PreparedPlan? = nil) async throws {
        try await coordinator.ensure(plan, prepared: prepared, ticket: await coordinator.ticket())
    }

    func remove() { folder.remove() }
}
