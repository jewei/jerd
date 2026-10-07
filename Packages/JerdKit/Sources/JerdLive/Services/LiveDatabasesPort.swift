import Foundation
import JerdDatabases
import JerdFoundation
import JerdUI

/// The Databases port on the one `DatabaseManager`. Its load installs the bundled runtimes of
/// engines that have none yet; a failed bundled setup leaves the load usable.
package struct LiveDatabasesPort: DatabasesPort {
    let manager: any DatabaseManaging
    let runtimes: any ServiceRuntimeSource
    let layout: DatabasesLayout
    let setup: BundledSetupRecord

    package init(
        manager: any DatabaseManaging, runtimes: any ServiceRuntimeSource, layout: DatabasesLayout,
        setup: BundledSetupRecord = BundledSetupRecord()
    ) {
        self.manager = manager
        self.runtimes = runtimes
        self.layout = layout
        self.setup = setup
    }

    package init(domain: LiveDomain) {
        self.init(
            manager: domain.databases, runtimes: BundledServiceRuntimes(bootstrap: domain.bootstrap),
            layout: domain.layout.databases)
    }

    /// Loads the registry first: a corrupt `services.json` fails here and nothing is installed.
    package func load() async throws -> DatabaseSnapshot {
        let configuration = try await manager.load()
        let registered = BundledRuntimeMapping.registeredKinds(configuration)
        if registered.count < DatabaseEngine.allCases.count {
            do {
                let installed = try await runtimes.databaseRuntimes(excluding: registered)
                if !installed.isEmpty { try await manager.registerRuntimes(installed) }
                await setup.record(nil)
            } catch {
                BundledServiceRuntimes.report(error, service: "database")
                await setup.record(BundledServiceRuntimes.message(for: error))
            }
        }
        return await manager.snapshot()
    }

    package func runtimeSetupFailure() async -> String? {
        await setup.failure
    }

    package func snapshot() async -> DatabaseSnapshot {
        await manager.snapshot()
    }

    package func files(for id: UUID) async -> ServiceFiles {
        let instance = layout.instance(id)
        return ServiceFilesProbe.files(dataFolder: instance.dataDirectory, log: instance.logFile)
    }

    package func suggestedPort(for engine: DatabaseEngine) async throws -> UInt16 {
        try await manager.suggestedPort(for: engine)
    }

    package func add(name: String, runtimeID: String, port: UInt16) async throws -> DatabaseService {
        try await manager.add(name: name, runtimeID: runtimeID, port: port)
    }

    package func edit(_ service: DatabaseService) async throws {
        try await manager.edit(service)
    }

    package func remove(_ id: UUID) async throws {
        try await manager.remove(id)
    }

    package func start(_ id: UUID) async throws {
        ServiceActivityLog.request("Start", "database \(id)")
        try await manager.start(id)
    }

    package func stop(_ id: UUID) async throws {
        ServiceActivityLog.request("Stop", "database \(id)")
        try await manager.stop(id)
    }

    package func stopAll() async throws {
        ServiceActivityLog.request("Stop", "every database")
        try await manager.stopAll()
    }

    package func connection(for id: UUID) async throws -> DatabaseConnection {
        try await manager.connection(for: id)
    }

    package func retainedDatabases() async throws -> [RetainedDatabase] {
        try await manager.retainedDatabases()
    }

    package func restoreRegistration(_ id: UUID, name: String, port: UInt16) async throws -> DatabaseService {
        try await manager.restoreRegistration(id, name: name, port: port)
    }
}
