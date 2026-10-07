import Foundation
import JerdFoundation
import JerdTunnels

/// Keeps tokens in memory. It can refuse writes to test the rollback paths.
actor FakeSecretStore: TunnelSecretStoring {
    private(set) var values: [UUID: String] = [:]
    var refusesWrites = false

    func setRefusesWrites(_ value: Bool) { refusesWrites = value }
    func set(_ token: String?, id: UUID) { values[id] = token }

    func read(id: UUID) -> String? { values[id] }

    func write(_ token: String, id: UUID) throws {
        guard !refusesWrites else { throw JerdError.unavailable("Keychain is locked.") }
        values[id] = token
    }

    func remove(id: UUID) { values[id] = nil }
}
