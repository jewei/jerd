import Foundation
import JerdFoundation
import JerdTestSupport
import JerdTunnels
import Testing

/// A loaded `TunnelSupervisor` with a fake connector, fake secrets, a manual clock, a runtime,
/// and one saved registration. Its waits follow `snapshotUpdates()`, so they need no real time.
struct SupervisorFixture {
    let folder: TemporaryDirectory
    let connector = FakeConnector()
    let secrets = FakeSecretStore()
    let clock = ManualClock()
    let supervisor: TunnelSupervisor
    let registration: TunnelRegistration

    init(restartOnFailure: Bool = true, startOnLaunch: Bool = false) async throws {
        folder = try TemporaryDirectory(" tunnels")
        supervisor = TunnelSupervisor(
            layout: folder.layout, secrets: secrets, connector: connector, policy: .standard, clock: clock)
        registration = TunnelRegistration(
            name: "Preview", hostname: "preview.example.com", startOnLaunch: startOnLaunch,
            restartOnFailure: restartOnFailure)
        try await supervisor.load()
        try await supervisor.useRuntime(at: URL(fileURLWithPath: "/runtimes/cloudflared/cloudflared"))
        try await supervisor.save(registration, token: TokenSamples.valid)
    }

    var id: UUID { registration.id }

    func state(_ id: UUID? = nil) async -> TunnelState? {
        await supervisor.snapshots().first { $0.registration.id == (id ?? registration.id) }?.state
    }

    func processID(_ id: UUID? = nil) async -> Int32? {
        await supervisor.snapshots().first { $0.registration.id == (id ?? registration.id) }?.processID
    }

    /// Returns when the snapshot of the tunnel meets `isMet`: at once, or after the change that
    /// makes it true. The suite's `.timeLimit` stops a test whose condition never comes.
    func until(_ id: UUID? = nil, _ isMet: @Sendable (TunnelSnapshot) -> Bool) async {
        let wanted = id ?? registration.id
        for await snapshots in await supervisor.snapshotUpdates() {
            if let snapshot = snapshots.first(where: { $0.registration.id == wanted }), isMet(snapshot) { return }
        }
    }

    /// Returns when the tunnel shows `expected`.
    func reach(_ expected: TunnelState, _ id: UUID? = nil) async {
        await until(id) { $0.state == expected }
    }

    /// Returns when the tunnel shows `expected` and Jerd owns no connector for it.
    func settle(_ expected: TunnelState) async {
        await until { $0.state == expected && $0.processID == nil }
    }

    /// Starts, then waits until the monitor sleeps before its next readiness check.
    func startAndSettle() async throws {
        try await supervisor.start(id: id)
        await clock.waitForSleeper(.seconds(5))
    }

    /// Adds a second registration with its own remote tunnel and metrics port.
    func addSecond() async throws -> TunnelRegistration {
        let second = TunnelRegistration(name: "Second", hostname: "two.example.com", metricsPort: 20_242)
        try await supervisor.save(second, token: TokenSamples.other)
        return second
    }

    /// Proves that a tunnel that failed by itself needs no Stop: a runtime change, an edit with a
    /// new token, Connect, and Remove all work at once.
    func expectNoStopNeeded() async throws {
        try await supervisor.useRuntime(at: URL(fileURLWithPath: "/runtimes/new/cloudflared"))
        try await supervisor.save(registration, token: TokenSamples.rotated)
        await connector.setOutputAtLaunch("")
        await connector.setConnectFailure(nil)
        await connector.setReadiness(.waiting)
        try await supervisor.start(id: id)
        try await supervisor.stop(id: id)
        try await supervisor.remove(id: id)
        #expect(await supervisor.snapshots().isEmpty)
    }
}
