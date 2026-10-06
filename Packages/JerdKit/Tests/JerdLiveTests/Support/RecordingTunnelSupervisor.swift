import Foundation
import JerdFoundation
import JerdTunnels

@testable import JerdLive

/// A tunnel supervisor that records each call and starts nothing.
actor RecordingTunnelSupervisor: TunnelControlling {
    private(set) var calls: [String] = []
    var stopAllFailure: JerdError?

    func failStopAll(_ error: JerdError) { stopAllFailure = error }

    func load() -> TunnelConfiguration {
        calls.append("load")
        return TunnelConfiguration()
    }

    func currentConfiguration() -> TunnelConfiguration { TunnelConfiguration() }
    func snapshots() -> [TunnelSnapshot] { [] }
    func suggestedPort() -> UInt16 { 20_241 }
    func save(_ registration: TunnelRegistration, token text: String?) { calls.append("save") }
    func remove(id: UUID) { calls.append("remove") }
    func start(id: UUID) { calls.append("start \(id)") }
    func stop(id: UUID) { calls.append("stop \(id)") }

    func stopAll() throws {
        calls.append("stopAll")
        if let stopAllFailure { throw stopAllFailure }
    }

    func connectStartupTunnels() -> [TunnelStartupFailure] {
        calls.append("connectStartupTunnels")
        return []
    }

    func log(id: UUID) -> String { "" }

    func useRuntime(at executable: URL) -> TunnelRuntime {
        calls.append("useRuntime \(executable.path)")
        return TunnelRuntime(version: "2026.1.0", directory: executable.deletingLastPathComponent())
    }
}
