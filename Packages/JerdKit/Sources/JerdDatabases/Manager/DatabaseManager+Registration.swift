import Foundation
import JerdFoundation
import JerdServiceKit

extension DatabaseManager {
    /// Registers a new service (it does not start). The port must be free on every address.
    public func add(name: String, runtimeID: String, port: UInt16) async throws -> DatabaseService {
        try requireLoaded()
        let service = DatabaseService(name: name, runtimeID: runtimeID, port: port)
        _ = try DatabaseRegistry.adding(service, to: configuration)
        try await effects.ports.requireFree(port)
        // The registry can change while the port check waits, so the rules run again.
        let next = try DatabaseRegistry.adding(service, to: configuration)
        try save(next)
        return try lookup(service.id)
    }

    /// Renames a stopped service or moves it to another free port. Its runtime never changes.
    ///
    /// Other registry changes can complete while this call waits for the port check and the
    /// instance. So the saved registry is built from the current registry, with the rules checked
    /// again, and no wait between that step and the save.
    public func edit(_ service: DatabaseService) async throws {
        let old = try lookup(service.id)
        try begin(service.id)
        defer { operations.remove(service.id) }
        let proposed = try DatabaseRegistry.replacing(service, in: configuration)
        if old.port != service.port { try await effects.ports.requireFree(service.port) }
        guard let edited = proposed.service(service.id) else { throw DatabaseMessages.notRegistered }
        let next = try definition(for: edited)
        let instance = try instance(for: old)
        let previous = await instance.definition
        do {
            try await instance.replaceDefinition(next)
        } catch {
            throw DatabaseMessages.stopBeforeEditing
        }
        do {
            try save(DatabaseRegistry.replacing(service, in: configuration))
        } catch {
            // The instance is stopped and unchanged on disk, so the old definition always fits.
            // The save error is the one to report.
            try? await instance.replaceDefinition(previous)
            throw error
        }
    }

    /// Stops the service and removes its registration. Every data file stays.
    ///
    /// Folders with database files get `removed-registration.json` for Restore, written under the
    /// instance lock. A service that never created data leaves nothing to restore.
    public func remove(_ id: UUID) async throws {
        let service = try lookup(id)
        let runtime = try configuration.runtime(for: service)
        try begin(id)
        defer { operations.remove(id) }
        let instance = try instance(for: service)
        try await instance.stop()
        let files = DatabaseInstanceFiles(layout: layout.instance(id))
        if RetainedDatabaseCatalog.holdsDatabase(files) {
            let lease = try await instance.beginMaintenance()
            do {
                try MarkerFile.write(
                    RemovedRegistration(service: service, runtime: runtime), to: files.layout.removedRegistrationFile)
            } catch {
                await instance.endMaintenance(lease)
                throw error
            }
            await instance.endMaintenance(lease)
        }
        try save(DatabaseRegistry.removing(id, from: configuration))
        instances[id] = nil
    }

    /// The retained database folders. The size check runs off this actor.
    public func retainedDatabases() async throws -> [RetainedDatabase] {
        try requireLoaded()
        return try await RetainedDatabaseCatalog(layout: layout).list(excluding: configuration)
    }

    /// Registers retained data again under its original ID and runtime, with a new name and port.
    public func restoreRegistration(_ id: UUID, name: String, port: UInt16) async throws -> DatabaseService {
        try requireLoaded()
        guard configuration.service(id) == nil, operations.insert(id).inserted else {
            throw DatabaseMessages.alreadyRegisteredOrBusy
        }
        defer { operations.remove(id) }
        let instance = layout.instance(id)
        let catalog = RetainedDatabaseCatalog(layout: layout)
        do {
            try OwnedDirectory.requireContained(instance.root, in: layout.root)
        } catch {
            throw DatabaseMessages.retainedFolderInvalid
        }
        let lock = try InstanceLock.acquire(at: instance.lockFile, messages: DatabaseMessages.instance.lock)
        defer { lock.release() }
        _ = try effects.startGate.requireStopped(instance.record, holding: lock)
        let record = try catalog.record(for: id, configuration: configuration)
        try catalog.validate(record, configuration: configuration)
        let service = DatabaseService(id: id, name: name, runtimeID: record.runtime.id, port: port)
        _ = try DatabaseRegistry.adding(service, to: configuration)
        try await effects.ports.requireFree(port)
        try save(DatabaseRegistry.adding(service, to: configuration))
        instances[id] = nil
        return try lookup(id)
    }
}
