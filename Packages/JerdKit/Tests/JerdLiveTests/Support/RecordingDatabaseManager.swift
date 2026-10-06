import Foundation
import JerdDatabases
import JerdFoundation

@testable import JerdLive

/// A database manager in memory. It records the calls that the port forwards.
actor RecordingDatabaseManager: DatabaseManaging {
    private(set) var configuration: DatabaseConfiguration
    private(set) var registered: [[DatabaseRuntime]] = []
    private(set) var calls: [String] = []
    let loadFailure: JerdError?
    var stopAllFailure: JerdError?

    init(_ configuration: DatabaseConfiguration = DatabaseConfiguration(), loadFailure: JerdError? = nil) {
        self.configuration = configuration
        self.loadFailure = loadFailure
    }

    func failStopAll(_ error: JerdError) { stopAllFailure = error }

    func load() throws -> DatabaseConfiguration {
        calls.append("load")
        if let loadFailure { throw loadFailure }
        return configuration
    }

    func registerRuntimes(_ runtimes: [DatabaseRuntime]) {
        registered.append(runtimes)
        configuration.runtimes += runtimes
    }

    func snapshot() -> DatabaseSnapshot { DatabaseSnapshot(configuration: configuration, states: [:]) }
    func suggestedPort(for engine: DatabaseEngine) -> UInt16 { 3_307 }
    func add(name: String, runtimeID: String, port: UInt16) throws -> DatabaseService { throw unused }
    func edit(_ service: DatabaseService) { calls.append("edit") }
    func remove(_ id: UUID) { calls.append("remove \(id)") }
    func start(_ id: UUID) { calls.append("start \(id)") }
    func stop(_ id: UUID) { calls.append("stop \(id)") }

    func stopAll() throws {
        calls.append("stopAll")
        if let stopAllFailure { throw stopAllFailure }
    }

    func connection(for id: UUID) throws -> DatabaseConnection { throw unused }
    func retainedDatabases() -> [RetainedDatabase] { [] }
    func restoreRegistration(_ id: UUID, name: String, port: UInt16) throws -> DatabaseService { throw unused }

    private var unused: JerdError { .unavailable("Not used by this test.") }
}
