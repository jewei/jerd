import Foundation
import JerdFoundation
import JerdProcess
import JerdTunnels

/// Pretends to run connectors. Gates can hold a connect, a readiness check, or a disconnect
/// until the test releases them. The gates ignore cancellation, like a spawn that already began.
actor FakeConnector: TunnelConnecting {
    private(set) var launches: [TunnelLaunch] = []
    private(set) var disconnects: [TunnelConnectorHandle] = []
    private(set) var owned: [UUID: TunnelConnectorHandle] = [:]
    private var alive: Set<TunnelConnectorHandle> = []
    private var outputs: [UUID: String] = [:]
    private var nextProcessID: Int32 = 30_000
    private var gates: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var held: [String: Int] = [:]

    var readiness: TunnelReadiness = .waiting
    var heldReadinessResult: TunnelReadiness = .waiting
    var outputAtLaunch = ""
    var connectFailure: JerdError?
    var disconnectFailure: JerdError?

    func setReadiness(_ value: TunnelReadiness) { readiness = value }
    func setOutputAtLaunch(_ value: String) { outputAtLaunch = value }
    func setConnectFailure(_ value: JerdError?) { connectFailure = value }
    func setDisconnectFailure(_ value: JerdError?) { disconnectFailure = value }
    func setHeldReadinessResult(_ value: TunnelReadiness) { heldReadinessResult = value }
    func exit(_ id: UUID) { if let handle = owned[id] { alive.remove(handle) } }

    /// The next `count` calls named `name` ("connect", "readiness", "disconnect") wait for `release(name)`.
    func hold(_ name: String, count: Int = 1) { held[name, default: 0] += count }
    func waiting(_ name: String) -> Int { gates[name]?.count ?? 0 }
    func release(_ name: String) {
        for gate in gates.removeValue(forKey: name) ?? [] { gate.resume() }
    }

    func inspectRuntime(executable: URL) -> TunnelRuntime {
        TunnelRuntime(version: "2026.9.3", directory: executable.deletingLastPathComponent())
    }

    func suggestPort(startingAt first: UInt16, excluding reserved: Set<UInt16>) -> UInt16 {
        (first...UInt16.max).first { !reserved.contains($0) } ?? first
    }

    func connect(_ launch: TunnelLaunch) async throws -> TunnelConnectorHandle {
        launches.append(launch)
        await pass("connect")
        if let connectFailure { throw connectFailure }
        let handle = TunnelConnectorHandle(
            registrationID: launch.registration.id, process: ProcessToken(), processID: nextProcessID,
            metricsPort: launch.registration.metricsPort)
        nextProcessID += 1
        owned[launch.registration.id] = handle
        alive.insert(handle)
        outputs[launch.registration.id] = outputAtLaunch
        return handle
    }

    func ownedHandle(for id: UUID) -> TunnelConnectorHandle? { owned[id] }

    func isRunning(_ handle: TunnelConnectorHandle) -> Bool { alive.contains(handle) }

    func readiness(of handle: TunnelConnectorHandle) async -> TunnelReadiness {
        if held["readiness", default: 0] > 0 {
            await pass("readiness")
            return heldReadinessResult
        }
        return readiness
    }

    func disconnect(_ handle: TunnelConnectorHandle) async throws {
        guard owned[handle.registrationID] == handle else { return }
        disconnects.append(handle)
        await pass("disconnect")
        if let disconnectFailure { throw disconnectFailure }
        owned[handle.registrationID] = nil
        alive.remove(handle)
    }

    func currentOutput(for id: UUID) -> String { outputs[id] ?? "" }

    func history(for id: UUID) -> String? { outputs[id] }

    private func pass(_ name: String) async {
        guard let count = held[name], count > 0 else { return }
        held[name] = count - 1
        await withCheckedContinuation { gates[name, default: []].append($0) }
    }
}
