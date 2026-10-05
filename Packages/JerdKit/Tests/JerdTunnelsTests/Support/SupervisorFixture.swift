import Foundation
import JerdFoundation
import JerdTunnels
import Testing

/// A loaded `TunnelSupervisor` with a fake connector, fake secrets, a manual clock, a runtime,
/// and one saved registration.
struct SupervisorFixture {
    let folder: TemporaryDirectory
    let connector = FakeConnector()
    let secrets = FakeSecretStore()
    let clock = ManualClock()
    let supervisor: TunnelSupervisor
    let registration: TunnelRegistration

    init(restartOnFailure: Bool = true, startOnLaunch: Bool = false) async throws {
        folder = try TemporaryDirectory()
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

    /// Waits until the tunnel shows `expected`.
    func reach(_ expected: TunnelState, _ id: UUID? = nil) async -> Bool {
        await eventually { await state(id) == expected }
    }

    /// Starts, then waits until the monitor sleeps before its next readiness check.
    func startAndSettle() async throws {
        try await supervisor.start(id: id)
        #expect(await clock.waitForSleeper(.seconds(5)))
    }

    /// Adds a second registration with its own remote tunnel and metrics port.
    func addSecond() async throws -> TunnelRegistration {
        let second = TunnelRegistration(name: "Second", hostname: "two.example.com", metricsPort: 20_242)
        try await supervisor.save(second, token: TokenSamples.other)
        return second
    }
}
