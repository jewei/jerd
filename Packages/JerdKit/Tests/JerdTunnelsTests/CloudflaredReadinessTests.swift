import Foundation
import JerdProcess
import JerdTunnels
import Testing

@Suite struct CloudflaredReadinessTests {
    private func connected() async throws -> (ConnectorFixture, TunnelConnectorHandle) {
        let fixture = try ConnectorFixture()
        let handle = try await fixture.connector.connect(try fixture.launch())
        return (fixture, handle)
    }

    @Test func anOwnedConnectorWithItsOnlyListenerAnd200IsReady() async throws {
        let (fixture, handle) = try await connected()
        defer { fixture.folder.remove() }
        #expect(try await fixture.connector.readiness(of: handle) == .ready)
        let executables = fixture.commands.commandLines.suffix(3).map(\.first)
        #expect(executables == ["/usr/sbin/lsof", "/usr/sbin/lsof", "/usr/bin/curl"])
    }

    @Test func noListenerYetMeansWaiting() async throws {
        let (fixture, handle) = try await connected()
        defer { fixture.folder.remove() }
        fixture.commands.replaceScript { _, _ in CommandResult(status: 1, output: "") }
        #expect(try await fixture.connector.readiness(of: handle) == .waiting)
    }

    @Test func aWildcardOrExtraListenerIsUnexpected() async throws {
        let (fixture, handle) = try await connected()
        defer { fixture.folder.remove() }
        fixture.commands.replaceScript { _, _ in CommandResult(status: 0, output: "p50000\nn*:20241\n") }
        #expect(try await fixture.connector.readiness(of: handle) == .unexpectedListener)
    }

    @Test func aSharedMetricsPortIsUnexpected() async throws {
        let (fixture, handle) = try await connected()
        defer { fixture.folder.remove() }
        let healthy = RecordingCommandRunner.healthy()
        fixture.commands.replaceScript { executable, arguments in
            arguments.contains("-Fp")
                ? CommandResult(status: 0, output: "p50000\np777\n") : healthy(executable, arguments)
        }
        #expect(try await fixture.connector.readiness(of: handle) == .unexpectedListener)
    }

    @Test func aReadyEndpointThatIsNot200MeansWaiting() async throws {
        let (fixture, handle) = try await connected()
        defer { fixture.folder.remove() }
        fixture.commands.replaceScript(RecordingCommandRunner.healthy(readyStatus: "503"))
        #expect(try await fixture.connector.readiness(of: handle) == .waiting)
    }

    @Test func anExitedOrUnknownConnectorIsNeverReadyAndRunsNoCommand() async throws {
        let (fixture, handle) = try await connected()
        defer { fixture.folder.remove() }
        let before = fixture.commands.commandLines.count
        await fixture.processes.exit(handle.process)
        #expect(!(await fixture.connector.isRunning(handle)))
        #expect(try await fixture.connector.readiness(of: handle) == .waiting)
        let stranger = TunnelConnectorHandle(
            registrationID: UUID(), process: ProcessToken(), processID: 1, metricsPort: 20_241)
        #expect(try await fixture.connector.readiness(of: stranger) == .waiting)
        #expect(fixture.commands.commandLines.count == before)
    }
}
