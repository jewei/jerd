import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdTestSupport
import JerdTunnels
import Testing

@Suite struct CloudflaredConnectorTests {
    @Test func cloudflareRoutingNeverRequiresTheReferencedSite() async throws {
        let sites = FakeTunnelSiteResolver()
        await sites.fail()
        let fixture = try ConnectorFixture(sites: sites)
        defer { fixture.folder.remove() }
        var registration = fixture.registration
        registration.siteID = UUID()
        let handle = try await fixture.connector.connect(
            TunnelLaunch(
                runtime: fixture.runtime, registration: registration, token: try TunnelToken(TokenSamples.valid)))
        #expect(contents(fixture.instance.configurationFile) == Data("{}\n".utf8))
        #expect(await sites.requests.isEmpty)
        try await fixture.connector.disconnect(handle)
    }

    @Test func localRoutingIsWrittenBeforeSpawnAndResolvesTheSiteAgainOnRestart() async throws {
        let sites = FakeTunnelSiteResolver()
        let fixture = try ConnectorFixture(sites: sites)
        defer { fixture.folder.remove() }
        var registration = fixture.registration
        registration.routing = .local
        registration.siteID = UUID()
        let launch = TunnelLaunch(
            runtime: fixture.runtime, registration: registration, token: try TunnelToken(TokenSamples.valid))
        let first = try await fixture.connector.connect(launch)
        let firstConfig = text(fixture.instance.configurationFile)
        #expect(firstConfig.contains("shop.test"))
        #expect(!firstConfig.contains(TokenSamples.valid))
        #expect(!firstConfig.contains(TokenSamples.secret))
        try await fixture.connector.disconnect(first)
        await sites.rename("renamed.test")
        let second = try await fixture.connector.connect(launch)
        #expect(text(fixture.instance.configurationFile).contains("renamed.test"))
        #expect(!text(fixture.instance.configurationFile).contains("shop.test"))
        #expect(await sites.requests.count == 2)
        try await fixture.connector.disconnect(second)
    }

    @Test func anUnavailableLocalSiteStopsBeforeSpawnAndKeepsThePreviousConfig() async throws {
        let sites = FakeTunnelSiteResolver()
        await sites.fail()
        let fixture = try ConnectorFixture(sites: sites)
        defer { fixture.folder.remove() }
        try OwnedDirectory.create(fixture.instance.root)
        try AtomicFile.write(Data("previous config".utf8), to: fixture.instance.configurationFile)
        var registration = fixture.registration
        registration.routing = .local
        registration.siteID = UUID()
        await #expect(throws: JerdError.unavailable("Start the linked site first.")) {
            try await fixture.connector.connect(
                TunnelLaunch(
                    runtime: fixture.runtime, registration: registration, token: try TunnelToken(TokenSamples.valid)))
        }
        #expect(await fixture.processes.started.isEmpty)
        #expect(text(fixture.instance.configurationFile) == "previous config")
        #expect(fixture.lockIsFree())
    }

    @Test func aLaunchPreparesTheFolderLocksItAndSavesTheRunRecord() async throws {
        let fixture = try ConnectorFixture()
        defer { fixture.folder.remove() }
        let handle = try await fixture.connector.connect(try fixture.launch())
        let instance = fixture.instance
        #expect(handle.processID == 50_000)
        #expect(handle.metricsPort == 20_241)
        #expect(contents(instance.configurationFile) == Data("{}\n".utf8))
        #expect(FileProbe.presence(at: instance.homeDirectory) == .present)
        #expect(!fixture.lockIsFree())
        let record = try ActiveRunRecordFile.read(instance.activeRunFile)
        #expect(record.processID == 50_000)
        #expect(record.runtimeID == "cloudflared-2026.9.3")
        #expect(record.gracefulSignal == SIGTERM)
        let request = try #require(await fixture.processes.started.first)
        #expect(request.environment["TUNNEL_TOKEN"] == TokenSamples.valid)
        #expect(!request.arguments.joined(separator: " ").contains(TokenSamples.valid))
        #expect(await fixture.connector.ownedHandle(for: fixture.registration.id) == handle)
    }

    @Test func aStopRemovesTheRecordAndReleasesTheLock() async throws {
        let fixture = try ConnectorFixture()
        defer { fixture.folder.remove() }
        let handle = try await fixture.connector.connect(try fixture.launch())
        try await fixture.connector.disconnect(handle)
        #expect(FileProbe.presence(at: fixture.instance.activeRunFile) == .absent)
        #expect(fixture.lockIsFree())
        #expect(await fixture.connector.ownedHandle(for: fixture.registration.id) == nil)
        try await fixture.connector.disconnect(handle)
        #expect(await fixture.processes.stopped.count == 1)
    }

    @Test func aStopTimeoutKeepsTheProcessTheRecordAndTheLock() async throws {
        let fixture = try ConnectorFixture()
        defer { fixture.folder.remove() }
        let handle = try await fixture.connector.connect(try fixture.launch())
        await fixture.processes.setStopOutcome(.timedOut(leaderRunning: true))
        await #expect(throws: JerdError.processFailed(TunnelMessage.notStopped)) {
            try await fixture.connector.disconnect(handle)
        }
        #expect(await fixture.connector.ownedHandle(for: fixture.registration.id) == handle)
        #expect(FileProbe.presence(at: fixture.instance.activeRunFile) == .present)
        #expect(!fixture.lockIsFree())
    }

    @Test func aLeaderThatSomethingElseReapedKeepsItsRecordForInspection() async throws {
        let fixture = try ConnectorFixture()
        defer { fixture.folder.remove() }
        let handle = try await fixture.connector.connect(try fixture.launch())
        await fixture.processes.setStopOutcome(.notOwned)
        try await fixture.connector.disconnect(handle)
        #expect(FileProbe.presence(at: fixture.instance.activeRunFile) == .present)
        #expect(fixture.lockIsFree())
        #expect(await fixture.connector.ownedHandle(for: fixture.registration.id) == nil)
    }

    @Test func aLiveEarlierProcessIsPreservedWithoutRunningAnyCommand() async throws {
        let fixture = try ConnectorFixture()
        defer { fixture.folder.remove() }
        try OwnedDirectory.create(fixture.instance.root)
        let bytes = Data(#"{"processID":\#(getpid()),"runtimeID":"cloudflared-test"}"#.utf8)
        try AtomicFile.write(bytes, to: fixture.instance.activeRunFile)
        let error = try await #require(throws: JerdError.self) {
            try await fixture.connector.connect(try fixture.launch())
        }
        #expect(error.message.hasPrefix("A previous service process needs inspection (PID \(getpid())). "))
        #expect(contents(fixture.instance.activeRunFile) == bytes)
        #expect(fixture.commands.commandLines.isEmpty)
        #expect(fixture.portCommands.commandLines.isEmpty)
        #expect(await fixture.processes.started.isEmpty)
        #expect(fixture.lockIsFree())
    }

    @Test func aDifferentRuntimeVersionStopsTheLaunch() async throws {
        let fixture = try ConnectorFixture()
        defer { fixture.folder.remove() }
        fixture.commands.replaceScript(RecordingCommandRunner.healthy(version: "2026.10.0"))
        await #expect(throws: JerdError.unavailable(TunnelMessage.versionMismatch)) {
            try await fixture.connector.connect(try fixture.launch())
        }
        #expect(await fixture.processes.started.isEmpty)
        #expect(fixture.lockIsFree())
    }

    @Test func anOccupiedMetricsPortStopsTheLaunch() async throws {
        let fixture = try ConnectorFixture()
        defer { fixture.folder.remove() }
        fixture.portCommands.replaceScript { _, _ in CommandResult(status: 0, output: "p999\n") }
        await #expect(throws: JerdError.unavailable("Local port 20241 is occupied. No process was stopped.")) {
            try await fixture.connector.connect(try fixture.launch())
        }
        #expect(await fixture.processes.started.isEmpty)
        #expect(fixture.lockIsFree())
    }

    @Test func aSecondLaunchWaitsForTheFirstToStop() async throws {
        let fixture = try ConnectorFixture()
        defer { fixture.folder.remove() }
        _ = try await fixture.connector.connect(try fixture.launch())
        await #expect(throws: JerdError.unavailable(TunnelMessage.previousProcess)) {
            try await fixture.connector.connect(try fixture.launch())
        }
        #expect(await fixture.processes.started.count == 1)
    }

    @Test func anotherSessionThatHoldsTheLockBlocksTheLaunch() async throws {
        let fixture = try ConnectorFixture()
        defer { fixture.folder.remove() }
        try OwnedDirectory.create(fixture.instance.root)
        let other = try InstanceLock.acquire(
            at: fixture.instance.lockFile, messages: InstanceLock.Messages(unavailable: "U.", busy: "B."))
        defer { other.release() }
        await #expect(throws: JerdError.locked(TunnelMessage.lockBusy)) {
            try await fixture.connector.connect(try fixture.launch())
        }
        #expect(fixture.commands.commandLines.isEmpty)
    }

    @Test func aChildWithoutAProcessIDIsReported() async throws {
        let fixture = try ConnectorFixture()
        defer { fixture.folder.remove() }
        await fixture.processes.setGivesProcessID(false)
        await #expect(throws: TunnelRetryableError(.processFailed(TunnelMessage.exitedEarly))) {
            try await fixture.connector.connect(try fixture.launch())
        }
        #expect(await fixture.processes.stopped.count == 1)
        #expect(await fixture.connector.ownedHandle(for: fixture.registration.id) == nil)
        #expect(fixture.lockIsFree())
    }

    @Test func aRecordFailureStopsTheNewConnector() async throws {
        let fixture = try ConnectorFixture(capture: { _ in throw JerdError.unavailable("Cannot inspect.") })
        defer { fixture.folder.remove() }
        await #expect(throws: JerdError.unavailable("Cannot inspect.")) {
            try await fixture.connector.connect(try fixture.launch())
        }
        #expect(await fixture.processes.stopped.count == 1)
        #expect(await fixture.connector.ownedHandle(for: fixture.registration.id) == nil)
        #expect(FileProbe.presence(at: fixture.instance.activeRunFile) == .absent)
        #expect(fixture.lockIsFree())
    }

    /// Regression test: a new connector run erased the output of the run before it.
    @Test func aNewLaunchKeepsTheOutputOfTheRunBefore() async throws {
        let fixture = try ConnectorFixture()
        defer { fixture.folder.remove() }
        await fixture.processes.setOutput("first run crashed\n")
        let first = try await fixture.connector.connect(try fixture.launch())
        try await fixture.connector.disconnect(first)
        await fixture.processes.setOutput("second run\n")
        _ = try await fixture.connector.connect(try fixture.launch())
        let id = fixture.registration.id
        #expect(try await fixture.connector.currentOutput(for: id) == "second run\n")
        let history = try #require(try await fixture.connector.history(for: id))
        #expect(history == "first run crashed\n\(ConnectorLogHistory.boundary)second run\n")
    }

    @Test func aRuntimeIsCheckedByNameAndVersionOutput() async throws {
        let fixture = try ConnectorFixture()
        defer { fixture.folder.remove() }
        let runtime = try await fixture.connector.inspectRuntime(executable: fixture.runtime.executable)
        #expect(runtime == fixture.runtime)
        #expect(fixture.commands.commandLines == [[fixture.runtime.executable.path, "--version"]])
        await #expect(throws: JerdError.invalid(TunnelMessage.executableName)) {
            try await fixture.connector.inspectRuntime(executable: URL(fileURLWithPath: "/bin/ls"))
        }
        fixture.commands.replaceScript { _, _ in CommandResult(status: 0, output: "other version 2026.9.3") }
        await #expect(throws: JerdError.invalid(TunnelMessage.noVersion)) {
            try await fixture.connector.inspectRuntime(executable: fixture.runtime.executable)
        }
        #expect(fixture.commands.commandLines.count == 2)
    }
}
