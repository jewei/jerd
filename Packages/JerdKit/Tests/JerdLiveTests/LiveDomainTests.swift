import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdLive

@Suite("Live domain wiring")
struct LiveDomainTests {
    static func configuration() throws -> LiveConfiguration {
        let app = try Fixture.temporaryFolder().appendingPathComponent("Jerd.app", isDirectory: true)
        return LiveConfiguration(
            layout: try Fixture.layout(), appBundle: app, resources: app.appendingPathComponent("Contents/Resources"),
            appVersion: "0.1.0")
    }

    @Test func servicesAndTunnelsShareOneGracefulSupervisor() async throws {
        let domain = LiveDomain(configuration: try Self.configuration(), helper: RecordingHelper())

        #expect(await domain.processes.ceiling == .graceful)
        #expect((domain.effects.processes as? ProcessSupervisor) === domain.processes)
    }

    @Test func theWebEngineHasItsOwnForcefulSupervisor() async throws {
        let engine = WebDomain.engineServices()
        let supervisor = try #require(engine.processes as? ProcessSupervisor)

        #expect(await supervisor.ceiling == .forceful)
    }

    @Test func dataServicesStopGracefullyWithinThirtySeconds() throws {
        let domain = LiveDomain(configuration: try Self.configuration(), helper: RecordingHelper())

        #expect(domain.effects.stopTimeout == .seconds(30))
    }

    @Test func buildingTheDomainChangesNothingOnDisk() throws {
        let configuration = try Self.configuration()

        _ = LiveDomain(configuration: configuration, helper: RecordingHelper())

        #expect(!FileManager.default.fileExists(atPath: configuration.layout.root.path))
    }

    @Test func payloadsAreInTheResourcesFolder() throws {
        let configuration = try Self.configuration()

        #expect(configuration.payloads.path == configuration.resources.appendingPathComponent("RuntimePayloads").path)
    }
}
