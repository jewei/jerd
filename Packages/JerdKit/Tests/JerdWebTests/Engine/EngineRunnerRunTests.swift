import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import Testing

@testable import JerdWeb

@Suite struct EngineRunnerRunTests {
    @Test func aRuntimeExitFailsTheRunOnceAndStopsEverything() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let layout = try harness.layout()
        let run = try await harness.start(try harness.plan(), layout: layout)
        let failure = Task { await harness.engine.waitForFailure(of: run) }
        await harness.processes.crash(where: "-F")
        #expect(await failure.value == EngineRunner.exitMessage)
        #expect(await harness.engine.state == .failed(EngineRunner.exitMessage))
        #expect(await harness.processes.allStopped)
        #expect(isAbsent(layout.socketDirectory))
        #expect(await harness.engine.waitForFailure(of: run) == EngineRunner.exitMessage)
    }

    @Test func aNormalStopEndsTheRunWithoutAFailure() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let run = try await harness.start(try harness.plan(), layout: try harness.layout())
        let failure = Task { await harness.engine.waitForFailure(of: run) }
        await harness.engine.stop()
        #expect(await failure.value == nil)
        #expect(await harness.engine.state == .stopped)
    }

    @Test func aStopRequestDuringStartCancelsItAndEndsStoppedNotFailed() async throws {
        let harness = try EngineHarness(
            httpsReady: false, timings: ReadinessTimings(tlsBudget: .seconds(30), tlsPoll: .milliseconds(5)))
        defer { harness.remove() }
        let layout = try harness.layout()
        let start = Task { try await harness.start(try harness.plan(), layout: layout) }
        #expect(await waitUntil { await harness.processes.startCount == 2 })
        await harness.engine.requestStop()
        await #expect(throws: CancellationError.self) { try await start.value }
        #expect(await harness.engine.state == .stopped)
        #expect(await harness.processes.allStopped)
    }

    @Test func httpsThatNeverAnswersFailsWithTheLastDiagnostic() async throws {
        let harness = try EngineHarness(
            httpsReady: false, timings: ReadinessTimings(tlsBudget: .milliseconds(100), tlsPoll: .milliseconds(5)))
        defer { harness.remove() }
        await #expect(throws: JerdError.processFailed("TLS readiness failed: curl: (7) not ready")) {
            try await harness.start(try harness.plan(), layout: try harness.layout())
        }
        #expect(await harness.processes.allStopped)
    }

    @Test func healthNeedsARunningRunAndAnsweringPools() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        #expect(await !harness.engine.isHealthy())
        _ = try await harness.start(try harness.plan(), layout: try harness.layout())
        #expect(await harness.engine.isHealthy())
        harness.pinger.fail(true)
        #expect(await !harness.engine.isHealthy())
        await harness.engine.stop()
    }

    @Test func aSecondStartWhileRunningIsRefused() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        _ = try await harness.start(try harness.plan(), layout: try harness.layout())
        await #expect(throws: JerdError.processFailed("The engine is already active.")) {
            try await harness.start(try harness.plan(), layout: try harness.layout())
        }
        await harness.engine.stop()
    }

    @Test func invalidPlansAreRefusedBeforeAnyChange() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let layout = try harness.layout()
        let plan = try harness.plan()
        var disabled = plan.sites[0].site
        disabled.isEnabled = false
        let cases: [(ServingPlan, JerdError)] = [
            (ServingPlan(sites: [], caddy: plan.caddy), .invalid("Enable the sites before starting them.")),
            (
                ServingPlan(sites: [PlannedSite(site: disabled, runtime: plan.sites[0].runtime)], caddy: plan.caddy),
                .invalid("Enable the sites before starting them.")
            ),
            (
                ServingPlan(sites: plan.sites + plan.sites, caddy: plan.caddy),
                .invalid("The serving plan contains a duplicate site ID.")
            ),
        ]
        for (plan, error) in cases {
            await #expect(throws: error) { try await harness.start(plan, layout: layout) }
        }
        await #expect(throws: JerdError.invalid("Listener ports do not match the engine request.")) {
            try await harness.engine.start(
                plan, layout: layout, binding: ListenerBinding(httpsPort: 1, httpPort: 2, inherited: true),
                listeners: harness.listeners.inherited)
        }
        #expect(await harness.processes.startCount == 0)
        #expect(await harness.engine.state != .running)
    }

    @Test func preflightValidatesInAThrowawayLayoutWithoutLaunching() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let layout = RunLayout.preflight(within: harness.environment)
        try await harness.engine.preflight(try harness.plan(), layout: layout)
        #expect(await harness.processes.startCount == 0)
        #expect(isAbsent(layout.socketDirectory))
        let caddy = text(layout.environment.caddyConfigurationFile)
        #expect(caddy.contains("127.0.0.1:18443") && caddy.contains("jerd-test"))
        #expect(harness.commands.arguments.contains { $0.last == "-t" })
        #expect(harness.commands.arguments.contains { $0.first == "validate" })
        try FileManager.default.removeItem(at: layout.preflightTree)
    }

    @Test func preflightRefusesARuntimeThatChangedSinceInspection() async throws {
        let harness = try EngineHarness()
        defer { harness.remove() }
        let plan = try harness.plan(runtimes: [Samples.runtime(version: "8.3.0")])
        await #expect(
            throws: JerdError.unavailable("PHP changed since inspection. Inspect and select the runtime again.")
        ) {
            try await harness.engine.preflight(plan, layout: RunLayout.preflight(within: harness.environment))
        }
    }

    @Test func listenerPortsRequireListeningLoopbackSockets() throws {
        let listeners = try TestListeners()
        defer { listeners.close() }
        let ports = try ListenerPorts.read(listeners.inherited)
        #expect(ports.http == listeners.httpPort && ports.https == listeners.httpsPort)
        let bound = try TestListeners.bind(listening: false)
        #expect(throws: JerdError.invalid("Expected a bound IPv4 loopback TCP socket.")) {
            try ListenerPorts.port(of: bound.handle.fileDescriptor)
        }
        let null = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/null"))
        #expect(throws: JerdError.self) { try ListenerPorts.port(of: null.fileDescriptor) }
    }
}
