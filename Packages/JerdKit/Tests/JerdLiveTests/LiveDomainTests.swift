import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdLive

@Suite("Live domain wiring")
struct LiveDomainTests {
    static func configuration(in temporary: TemporaryDirectory) throws -> LiveConfiguration {
        let root = temporary.path(UUID().uuidString)
        let app = root.appendingPathComponent("Jerd.app", isDirectory: true)
        return LiveConfiguration(
            layout: DataLayout(root: root.appendingPathComponent("Jerd", isDirectory: true)), appBundle: app,
            resources: app.appendingPathComponent("Contents/Resources"),
            appVersion: "0.1.0")
    }

    @Test func servicesAndTunnelsShareOneGracefulSupervisor() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let domain = LiveDomain(configuration: try Self.configuration(in: temporary), helper: RecordingHelper())

        #expect(await domain.processes.ceiling == .graceful)
        #expect((domain.effects.processes as? ProcessSupervisor) === domain.processes)
    }

    @Test func theWebEngineHasItsOwnForcefulSupervisor() async throws {
        let engine = WebDomain.engineServices()
        let supervisor = try #require(engine.processes as? ProcessSupervisor)

        #expect(await supervisor.ceiling == .forceful)
    }

    @Test func dataServicesStopGracefullyWithinThirtySeconds() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let domain = LiveDomain(configuration: try Self.configuration(in: temporary), helper: RecordingHelper())

        #expect(domain.effects.stopTimeout == .seconds(30))
    }

    @Test func buildingTheDomainChangesNothingOnDisk() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let configuration = try Self.configuration(in: temporary)

        _ = LiveDomain(configuration: configuration, helper: RecordingHelper())

        #expect(!FileManager.default.fileExists(atPath: configuration.layout.root.path))
    }

    @Test func payloadsAreInTheResourcesFolder() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let configuration = try Self.configuration(in: temporary)

        #expect(configuration.payloads.path == configuration.resources.appendingPathComponent("RuntimePayloads").path)
    }
}
