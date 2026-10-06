import Foundation
import JerdDatabases

/// The database manager calls that the live ports use. `DatabaseManager` is the live type.
package protocol DatabaseManaging: Sendable {
    func load() async throws -> DatabaseConfiguration
    func registerRuntimes(_ runtimes: [DatabaseRuntime]) async throws
    func snapshot() async -> DatabaseSnapshot
    func suggestedPort(for engine: DatabaseEngine) async throws -> UInt16
    func add(name: String, runtimeID: String, port: UInt16) async throws -> DatabaseService
    func edit(_ service: DatabaseService) async throws
    func remove(_ id: UUID) async throws
    func start(_ id: UUID) async throws
    func stop(_ id: UUID) async throws
    func stopAll() async throws
    func connection(for id: UUID) async throws -> DatabaseConnection
    func retainedDatabases() async throws -> [RetainedDatabase]
    func restoreRegistration(_ id: UUID, name: String, port: UInt16) async throws -> DatabaseService
}

extension DatabaseManager: DatabaseManaging {}
