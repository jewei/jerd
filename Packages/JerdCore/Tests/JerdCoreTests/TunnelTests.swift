import Foundation
import Testing
import Darwin
@testable import JerdCore

private actor TunnelMemorySecrets: TunnelSecretStoring {
    var values: [UUID: String] = [:]
    func read(id: UUID) -> String? { values[id] }
    func write(_ token: String, id: UUID) { values[id] = token }
    func remove(id: UUID) { values[id] = nil }
}
private actor TunnelFakeTransport: TunnelTransport {
    var owned: [UUID: TunnelProcess] = [:]
    var alive = true
    var ready = false
    var startCount = 0
    var stopCount = 0
    var failStop = false
    var invalidListener = false
    var suspendStart = false
    var startGate: CheckedContinuation<Void, Never>?
    var startupMessage = ""
    var suspendStop = false
    var stopGate: CheckedContinuation<Void, Never>?
    var suspendReadiness = false
    var readinessGate: CheckedContinuation<Void, Never>?
    func inspectRuntime(executable: URL, directory: URL) -> TunnelRuntime { tunnelRuntime }
    func availablePort(startingAt: UInt16, excluding: Set<UInt16>, directory: URL) -> UInt16 { startingAt }
    func start(runtime: TunnelRuntime, registration: TunnelRegistration, token: String, paths: TunnelPaths) async throws -> TunnelProcess {
        startCount += 1
        try PrivateFiles.directory(paths.root)
        try PrivateFiles.write(Data(startupMessage.utf8), to: paths.log)
        if suspendStart { await withCheckedContinuation { startGate = $0 } }
        let process = TunnelProcess(id: UUID(), processID: Int32(20_000 + startCount))
        owned[registration.id] = process
        alive = true
        return process
    }
    func ownedProcess(registrationID: UUID) -> TunnelProcess? { owned[registrationID] }
    func isRunning(_ process: TunnelProcess) -> Bool { alive && owned.values.contains(process) }
    func isReady(_ process: TunnelProcess, registration: TunnelRegistration, paths: TunnelPaths) async throws -> Bool {
        if suspendReadiness {
            suspendReadiness = false
            await withCheckedContinuation { readinessGate = $0 }
            throw TunnelTransportError.unexpectedListener
        }
        if invalidListener { throw TunnelTransportError.unexpectedListener }
        return ready
    }
    func stop(_ process: TunnelProcess, paths: TunnelPaths) async throws {
        stopCount += 1
        if suspendStop { await withCheckedContinuation { stopGate = $0 } }
        if failStop { throw JerdError.process("Graceful stop timed out.") }
        owned = owned.filter { $0.value != process }
    }
    func suspendNextStop() { suspendStop = true }
    func releaseStop() { suspendStop = false; stopGate?.resume(); stopGate = nil }
    func suspendNextReadiness() { suspendReadiness = true }
    func releaseReadinessError() { readinessGate?.resume(); readinessGate = nil }
    func setReady(_ value: Bool) { ready = value }
    func exit() { alive = false }
    func setFailStop(_ value: Bool) { failStop = value }
    func setInvalidListener() { invalidListener = true }
    func setSuspendStart() { suspendStart = true }
    func releaseStart() { startGate?.resume(); startGate = nil; suspendStart = false }
    func setStartupMessage(_ value: String) { startupMessage = value }
}
private let tunnelRuntime = TunnelRuntime(id: "cloudflared-2026.9.3", version: "2026.9.3", path: "/test/cloudflared")
private let tunnelToken = Data("{\"a\":\"account\",\"t\":\"32394787-9B89-41AE-A065-57520475754A\",\"s\":\"private-token-secret\"}".utf8).base64EncodedString()
private let fastTunnelPolicy = TunnelMonitorPolicy(interval: .milliseconds(5), retryDelays: [.milliseconds(15), .milliseconds(25)])
private func tunnelEventually(_ condition: @escaping @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Tunnel condition did not complete before the test deadline.")
}
private func preparedTunnel(root: URL, transport: TunnelFakeTransport, secrets: TunnelMemorySecrets = .init(), restart: Bool = true) async throws -> (TunnelManager, TunnelRegistration) {
    let manager = TunnelManager(directory: root, secrets: secrets, transport: transport, policy: fastTunnelPolicy)
    _ = try await manager.load()
    try await manager.registerRuntime(tunnelRuntime)
    let registration = TunnelRegistration(name: "Preview", hostname: "preview.example.com", restartOnFailure: restart)
    try await manager.save(registration, token: tunnelToken)
    return (manager, registration)
}

struct TunnelTests {
    @Test(arguments: [Data(), Data("{\"schemaVersion\":999,\"tunnels\":[]}".utf8)])
    func corruptSettingsArePreserved(_ bytes: Data) async throws {
        let root = try temporaryDirectory(" tunnel corruption")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("settings.json")
        try bytes.write(to: file)
        let store = TunnelStore(directory: root)
        await #expect(throws: (any Error).self) { try await store.load() }
        await #expect(throws: (any Error).self) { try await store.save(.init()) }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func tokensStayOutOfArgumentsAndSavedSettings() async throws {
        let root = try temporaryDirectory(" tunnel token")
        defer { try? FileManager.default.removeItem(at: root) }
        let secrets = TunnelMemorySecrets(), transport = TunnelFakeTransport()
        let (manager, registration) = try await preparedTunnel(root: root, transport: transport, secrets: secrets)
        let bytes = try Data(contentsOf: root.appendingPathComponent("settings.json"))
        #expect(!String(decoding: bytes, as: UTF8.self).contains(tunnelToken))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("private-token-secret"))
        #expect(await secrets.read(id: registration.id) == tunnelToken)
        let paths = TunnelPaths(root: root)
        let request = TunnelDriver.server(runtime: tunnelRuntime, registration: registration, token: tunnelToken, paths: paths)
        #expect(!request.arguments.joined(separator: " ").contains(tunnelToken))
        #expect(request.environment == ["HOME": paths.home.path, "TUNNEL_TOKEN": tunnelToken])
        #expect(request.arguments.contains(paths.config.path))
        #expect(request.arguments.contains("127.0.0.1:20241"))
        #expect(request.redactedValues.contains(tunnelToken))
        #expect(request.redactedValues.contains("private-token-secret"))
        #expect(await transport.startCount == 0)
        #expect(await manager.snapshots().first?.state == .stopped)
    }

    @Test func connectedRequiresOwnedConnectorReadiness() async throws {
        let root = try temporaryDirectory(" tunnel ready")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = TunnelFakeTransport()
        let (manager, registration) = try await preparedTunnel(root: root, transport: transport)
        try await manager.start(id: registration.id)
        try await tunnelEventually { await manager.snapshots().first?.state == .reconnecting }
        await transport.setReady(true)
        try await tunnelEventually { await manager.snapshots().first?.state == .connected }
        await transport.setReady(false)
        try await tunnelEventually { await manager.snapshots().first?.state == .reconnecting }
        try await manager.stopAll()
        #expect(await manager.snapshots().first?.state == .stopped)
    }

    @Test func unexpectedExitRestartsButExplicitStopDoesNot() async throws {
        let root = try temporaryDirectory(" tunnel restart")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = TunnelFakeTransport()
        let (manager, registration) = try await preparedTunnel(root: root, transport: transport)
        try await manager.start(id: registration.id)
        await transport.exit()
        try await tunnelEventually { await transport.startCount >= 2 }
        try await manager.stop(id: registration.id)
        let count = await transport.startCount
        try await Task.sleep(for: .milliseconds(80))
        #expect(await transport.startCount == count)
        #expect(await manager.snapshots().first?.processID == nil)
    }

    @Test func disabledRestartAndRejectedTokenStopRetrying() async throws {
        for authFailure in [true, false] {
            let root = try temporaryDirectory(" tunnel no restart")
            defer { try? FileManager.default.removeItem(at: root) }
            let transport = TunnelFakeTransport()
            let (manager, registration) = try await preparedTunnel(root: root, transport: transport, restart: authFailure)
            if authFailure { await transport.setStartupMessage("ERR Provided Tunnel token is not valid") }
            try await manager.start(id: registration.id)
            if !authFailure { await transport.exit() }
            try await tunnelEventually {
                if case .failed = await manager.snapshots().first?.state { return true }
                return false
            }
            try await Task.sleep(for: .milliseconds(60))
            #expect(await transport.startCount == 1)
            #expect(await manager.snapshots().first?.processID == nil)
            try await manager.stopAll()
        }
    }

    @Test func stopCancelsAnInFlightStartWithoutLeavingAProcess() async throws {
        let root = try temporaryDirectory(" tunnel start race")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = TunnelFakeTransport()
        await transport.setSuspendStart()
        let (manager, registration) = try await preparedTunnel(root: root, transport: transport)
        let starting = Task { try await manager.start(id: registration.id) }
        try await tunnelEventually { await transport.startGate != nil }
        let stopping = Task { try await manager.stop(id: registration.id) }
        try await tunnelEventually { await manager.snapshots().first?.state == .stopping }
        await transport.releaseStart()
        _ = await starting.result
        try await stopping.value
        try await Task.sleep(for: .milliseconds(50))
        #expect(await transport.owned.isEmpty)
        #expect(await transport.startCount == 1)
        #expect(await manager.snapshots().first?.state == .stopped)
    }

    @Test func gracefulStopFailureRetainsOwnershipAndToken() async throws {
        let root = try temporaryDirectory(" tunnel graceful stop")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = TunnelFakeTransport(), secrets = TunnelMemorySecrets()
        let (manager, registration) = try await preparedTunnel(root: root, transport: transport, secrets: secrets)
        try await manager.start(id: registration.id)
        await transport.setFailStop(true)
        await #expect(throws: (any Error).self) { try await manager.stop(id: registration.id) }
        #expect(await manager.snapshots().first?.processID != nil)
        #expect(await secrets.read(id: registration.id) == tunnelToken)
        await #expect(throws: (any Error).self) { try await manager.remove(id: registration.id) }
        await transport.setFailStop(false)
        try await manager.stop(id: registration.id)
        try await manager.remove(id: registration.id)
        #expect(await secrets.read(id: registration.id) == nil)
    }

    @Test func unexpectedListenerStopsTheOwnedProcess() async throws {
        let root = try temporaryDirectory(" tunnel listener")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = TunnelFakeTransport()
        await transport.setInvalidListener()
        let (manager, registration) = try await preparedTunnel(root: root, transport: transport)
        try await manager.start(id: registration.id)
        try await tunnelEventually { await transport.stopCount == 1 }
        #expect(await manager.snapshots().first?.processID == nil)
        #expect(await transport.startCount == 1)
        try await manager.stopAll()
    }

    @Test func concurrentStopsShareOneOperationBeforeAReplacementStarts() async throws {
        let root = try temporaryDirectory(" tunnel concurrent stops")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = TunnelFakeTransport()
        let (manager, registration) = try await preparedTunnel(root: root, transport: transport)
        try await manager.start(id: registration.id)
        await transport.suspendNextStop()
        let first = Task { try await manager.stop(id: registration.id) }
        try await tunnelEventually { await transport.stopGate != nil }
        let second = Task { try await manager.stop(id: registration.id) }
        try await Task.sleep(for: .milliseconds(20))
        #expect(await transport.stopCount == 1)
        await #expect(throws: (any Error).self) { try await manager.start(id: registration.id) }
        await transport.releaseStop()
        try await first.value
        try await second.value
        try await manager.start(id: registration.id)
        #expect(await manager.snapshots().first?.processID != nil)
        #expect(await transport.owned.count == 1)
        try await manager.stopAll()
    }

    @Test func staleReadinessErrorCannotStopAReplacementConnector() async throws {
        let root = try temporaryDirectory(" tunnel stale ready")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = TunnelFakeTransport()
        let (manager, registration) = try await preparedTunnel(root: root, transport: transport)
        await transport.suspendNextReadiness()
        try await manager.start(id: registration.id)
        try await tunnelEventually { await transport.readinessGate != nil }
        try await manager.stop(id: registration.id)
        await transport.setReady(true)
        try await manager.start(id: registration.id)
        try await tunnelEventually { await manager.snapshots().first?.state == .connected }
        let replacement = await manager.snapshots().first?.processID
        await transport.releaseReadinessError()
        try await Task.sleep(for: .milliseconds(30))
        #expect(await manager.snapshots().first?.state == .connected)
        #expect(await manager.snapshots().first?.processID == replacement)
        #expect(await transport.stopCount == 1)
        try await manager.stopAll()
    }

    @Test func previousUnverifiedProcessIsPreservedWithoutRunningAnyCommand() async throws {
        let root = try temporaryDirectory(" tunnel old process")
        defer { try? FileManager.default.removeItem(at: root) }
        let registration = TunnelRegistration(name: "Existing", hostname: "preview.example.com")
        let paths = TunnelPaths(root: root.appendingPathComponent("instances").appendingPathComponent(registration.id.uuidString))
        try PrivateFiles.directory(paths.root)
        let bytes = Data("{\"processID\":\(getpid()),\"runtimeID\":\"cloudflared-test\"}".utf8)
        try PrivateFiles.write(bytes, to: paths.activeRun)
        let transport = TunnelLocalTransport()
        await #expect(throws: (any Error).self) {
            try await transport.start(runtime: tunnelRuntime, registration: registration, token: tunnelToken, paths: paths)
        }
        #expect(try Data(contentsOf: paths.activeRun) == bytes)
        #expect(await transport.ownedProcess(registrationID: registration.id) == nil)
    }

    @Test func invalidRegistrationsAndDuplicatePortsCannotBeSaved() throws {
        for hostname in ["https://example.com", "example.com/path", "EXAMPLE.com", "bad..example.com", "-bad.example.com", "localhost", "127.0.0.1"] {
            #expect(throws: (any Error).self) { try TunnelRegistration(name: "Test", hostname: hostname).validate() }
        }
        for origin in ["https://public.example.com", "http://user:pass@127.0.0.1", "http://127.0.0.1/#fragment", "file:///tmp/file"] {
            #expect(throws: (any Error).self) { try TunnelRegistration(name: "Test", hostname: "example.com", originURL: origin).validate() }
        }
        try TunnelRegistration(name: "Test", hostname: "example.com", originURL: "https://localhost:8443").validate()
        let one = TunnelRegistration(name: "One", hostname: "one.example.com")
        let two = TunnelRegistration(name: "Two", hostname: "two.example.com")
        #expect(throws: (any Error).self) { try TunnelConfiguration(tunnels: [one, two]).validate() }
    }

    @Test func aSavedStartupPreferenceDoesNotStartOnLoad() async throws {
        let root = try temporaryDirectory(" tunnel saved startup")
        defer { try? FileManager.default.removeItem(at: root) }
        let registration = TunnelRegistration(name: "Startup", hostname: "preview.example.com", startOnLaunch: true)
        try await TunnelStore(directory: root).save(.init(runtime: tunnelRuntime, tunnels: [registration]))
        let transport = TunnelFakeTransport()
        let manager = TunnelManager(directory: root, secrets: TunnelMemorySecrets(), transport: transport)
        _ = try await manager.load()
        #expect(await transport.startCount == 0)
        #expect(await manager.snapshots().first?.state == .stopped)
    }
    @Test func saveFailureRestoresThePreviousTokenAndKeepsCorruptSettings() async throws {
        let root = try temporaryDirectory(" tunnel credential rollback")
        defer { try? FileManager.default.removeItem(at: root) }
        let secrets = TunnelMemorySecrets(), transport = TunnelFakeTransport()
        let (manager, registration) = try await preparedTunnel(root: root, transport: transport, secrets: secrets)
        let file = root.appendingPathComponent("settings.json")
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: file)
        let rotated = Data("{\"a\":\"account\",\"t\":\"32394787-9B89-41AE-A065-57520475754A\",\"s\":\"new-secret\"}".utf8).base64EncodedString()
        await #expect(throws: (any Error).self) { try await manager.save(registration, token: rotated) }
        #expect(await secrets.read(id: registration.id) == tunnelToken)
        #expect(try Data(contentsOf: file) == corrupt)
    }

    @Test func rotatedDuplicateAndMalformedTokensAreRejected() async throws {
        let root = try temporaryDirectory(" tunnel duplicate token")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = TunnelFakeTransport(), secrets = TunnelMemorySecrets()
        let (manager, _) = try await preparedTunnel(root: root, transport: transport, secrets: secrets)
        let second = TunnelRegistration(name: "Duplicate", hostname: "two.example.com", metricsPort: 20242)
        let rotated = Data("{\"a\":\"account\",\"t\":\"32394787-9B89-41AE-A065-57520475754A\",\"s\":\"new-secret\"}".utf8).base64EncodedString()
        for token in [rotated, "not-a-token", "cloudflared tunnel run --token secret", ""] {
            await #expect(throws: (any Error).self) { try await manager.save(second, token: token) }
        }
        #expect(await secrets.read(id: second.id) == nil)
        #expect(await manager.configurationSnapshot().tunnels.count == 1)
    }

    @Test func tunnelsRunIndependentlyAndKeepTokensAfterStop() async throws {
        let root = try temporaryDirectory(" tunnel multiple")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = TunnelFakeTransport(), secrets = TunnelMemorySecrets()
        let (manager, first) = try await preparedTunnel(root: root, transport: transport, secrets: secrets)
        let second = TunnelRegistration(name: "Second", hostname: "two.example.com", metricsPort: 20242)
        let token = Data("{\"a\":\"account\",\"t\":\"C52B93C8-AD2F-4F26-9252-9195BB7E236A\",\"s\":\"second-secret\"}".utf8).base64EncodedString()
        try await manager.save(second, token: token)
        try await manager.start(id: first.id)
        try await manager.start(id: second.id)
        await #expect(throws: (any Error).self) { try await manager.registerRuntime(tunnelRuntime) }
        try await manager.stop(id: first.id)
        #expect(await transport.owned.count == 1)
        #expect(await manager.snapshots().first(where: { $0.registration.id == second.id })?.processID != nil)
        #expect(await secrets.read(id: first.id) == tunnelToken)
        try await manager.stopAll()
        // A cancelled application quit permits a later explicit Connect.
        try await manager.start(id: first.id)
        try await manager.stopAll()
        #expect(await transport.owned.isEmpty)
        #expect(await secrets.values.count == 2)
    }

    @Test func stopDuringRetryBackoffPreventsTheNextStart() async throws {
        let root = try temporaryDirectory(" tunnel retry stop")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = TunnelFakeTransport(), secrets = TunnelMemorySecrets()
        let manager = TunnelManager(directory: root, secrets: secrets, transport: transport,
                                    policy: .init(interval: .milliseconds(5), retryDelays: [.milliseconds(100)]))
        _ = try await manager.load()
        try await manager.registerRuntime(tunnelRuntime)
        let registration = TunnelRegistration(name: "Retry", hostname: "preview.example.com")
        try await manager.save(registration, token: tunnelToken)
        try await manager.start(id: registration.id)
        await transport.exit()
        try await tunnelEventually { await transport.stopCount == 1 }
        try await manager.stop(id: registration.id)
        try await Task.sleep(for: .milliseconds(150))
        #expect(await transport.startCount == 1)
        #expect(await manager.snapshots().first?.state == .stopped)
    }

}
