import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdWeb

@Suite struct SystemSetupGatewayTests {
    struct Context {
        let folder: TemporaryDirectory
        let layout: DataLayout
        let system: FakeSystem
        let coordinator: FakeCoordinator
        let commands: ScriptedCommandRunner
        let gateway: SystemSetupGateway

        init(_ status: HTTPSSetupStatus = HTTPSSetupStatus(), running: ServingPlan? = nil) throws {
            folder = try TemporaryDirectory(" gateway")
            let layout = DataLayout(root: folder.url)
            self.layout = layout
            system = FakeSystem(status)
            coordinator = FakeCoordinator(running)
            commands = LocalCAProvisionerTests.creatingCaddy(layout.environment)
            gateway = SystemSetupGateway(layout: layout, system: system, coordinator: coordinator, commands: commands)
        }
    }

    @Test func prepareCreatesTheCAAndRequestsServerTrustForSortedHostnames() async throws {
        let context = try Context()
        defer { context.folder.remove() }
        try OwnedDirectory.create(context.layout.environment.root)
        try AtomicFile.write(
            Data(Certificates.installationID.uuidString.utf8), to: context.layout.environment.installationIDFile)
        let setup = try await context.gateway.prepare(hostnames: ["b.test", "A.test"], caddy: Samples.caddy())
        #expect(setup.hostnames == ["a.test", "b.test"])
        #expect(setup.registration.trustPolicy == .serverTLS)
        #expect(setup.registration.certificateDER == (try Certificates.authority().der))
        #expect(setup.fingerprint == (try Certificates.authority().fingerprint))
        #expect(context.commands.requests.count == 1)
        #expect(await context.system.configurations.isEmpty)
    }

    @Test func aMissingCAIsNotCreatedWhileSitesRun() async throws {
        let context = try Context(running: ServingPlan(sites: [], caddy: Samples.caddy()))
        defer { context.folder.remove() }
        await #expect(throws: JerdError.unavailable("Stop the environment before preparing a missing CA.")) {
            try await context.gateway.prepare(hostnames: ["a.test"], caddy: Samples.caddy())
        }
        #expect(context.commands.requests.isEmpty)
    }

    @Test func invalidHostnameSetsAreRefusedBeforeAnyChange() async throws {
        let context = try Context()
        defer { context.folder.remove() }
        await #expect(throws: JerdError.invalid("Each site needs a unique hostname.")) {
            try await context.gateway.prepare(hostnames: ["a.test", "A.test"], caddy: Samples.caddy())
        }
        #expect(isAbsent(context.layout.environment.installationIDFile))
    }

    @Test func applyStopsTheRunThenConfigures() async throws {
        let context = try Context()
        defer { context.folder.remove() }
        let setup = HTTPSSetup(registration: try FakeSystem.approved(["a.test"]).registration!)
        try await context.gateway.apply(setup)
        #expect(await context.coordinator.halts == 1)
        #expect(await context.system.configurations == [setup.registration])
    }

    @Test func removingHostnamesKeepsTheRestAndThePolicy() async throws {
        let context = try Context(try FakeSystem.approved(["a.test", "b.test", "c.test"], policy: .hostnames))
        defer { context.folder.remove() }
        try await context.gateway.removeHostnames(["b.test", "x.test"])
        let status = await context.system.status()
        #expect(status.hostnames == ["a.test", "c.test"] && status.trustPolicy == .hostnames)
        try await context.gateway.removeHostnames(["z.test"])
        #expect(await context.coordinator.halts == 1)
        try await context.gateway.removeHostnames(["a.test", "c.test"])
        #expect(await context.system.removals == 1)
    }

    @Test func removingHostnamesWithoutACertificateRecordIsRefused() async throws {
        var status = try FakeSystem.approved(["a.test", "b.test"])
        status.certificateDER = nil
        let context = try Context(status)
        defer { context.folder.remove() }
        await #expect(throws: JerdError.unavailable("The approved certificate record is missing.")) {
            try await context.gateway.removeHostnames(["a.test"])
        }
    }

    @Test func restoreRecreatesAStatusOrRemovesAnEmptyOne() async throws {
        let context = try Context()
        defer { context.folder.remove() }
        let saved = try FakeSystem.approved(["a.test"], policy: .hostnames)
        try await context.gateway.restore(saved)
        #expect(try await context.system.status() == saved)
        try await context.gateway.restore(HTTPSSetupStatus())
        #expect(await context.system.removals == 1)
        #expect(await context.coordinator.halts == 2)
    }

    @Test func removeSetupMarksTheEnvironment() async throws {
        let context = try Context(try FakeSystem.approved(["a.test"]))
        defer { context.folder.remove() }
        try await context.gateway.removeSetup()
        #expect(await context.system.removals == 1)
        #expect(await context.coordinator.setupRemoved)
    }
}
