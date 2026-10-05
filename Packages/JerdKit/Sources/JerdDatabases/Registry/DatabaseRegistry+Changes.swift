import Foundation
import JerdFoundation

extension DatabaseRegistry {
    /// Adds runtimes with new IDs. A known ID must name the same runtime.
    static func registering(
        _ runtimes: [DatabaseRuntime], in configuration: DatabaseConfiguration
    ) throws
        -> DatabaseConfiguration
    {
        var next = configuration
        for runtime in runtimes {
            if let existing = next.runtimes.first(where: { $0.id == runtime.id }) {
                guard existing == runtime else { throw DatabaseMessages.runtimeChanged }
            } else {
                next.runtimes.append(runtime)
            }
        }
        return next
    }

    /// Adds `service` with a trimmed name, after the port and name checks.
    static func adding(
        _ service: DatabaseService, to configuration: DatabaseConfiguration
    ) throws
        -> DatabaseConfiguration
    {
        let added = trimmed(service)
        try requireAvailable(added, in: configuration)
        var next = configuration
        next.services.append(added)
        return next
    }

    /// Renames or moves a registered service. Its runtime must not change.
    static func replacing(
        _ service: DatabaseService, in configuration: DatabaseConfiguration
    ) throws
        -> DatabaseConfiguration
    {
        guard let index = configuration.services.firstIndex(where: { $0.id == service.id }) else {
            throw DatabaseMessages.notRegistered
        }
        guard configuration.services[index].runtimeID == service.runtimeID else {
            throw DatabaseMessages.stopBeforeEditing
        }
        let edited = trimmed(service)
        try requireAvailable(edited, in: configuration)
        var next = configuration
        next.services[index] = edited
        return next
    }

    /// Removes the registration only. Data folders are never touched here.
    static func removing(_ id: UUID, from configuration: DatabaseConfiguration) -> DatabaseConfiguration {
        var next = configuration
        next.services.removeAll { $0.id == id }
        return next
    }

    /// Requires a valid name and port, and a port and trimmed name that no other service uses.
    static func requireAvailable(_ service: DatabaseService, in configuration: DatabaseConfiguration) throws {
        guard DatabaseConfiguration.isValidName(service.name), service.port >= 1_024 else {
            throw DatabaseMessages.serviceInvalid
        }
        let others = configuration.services.filter { $0.id != service.id }
        if let owner = others.first(where: { $0.port == service.port }) {
            throw DatabaseMessages.portConflict(service.port, with: owner.name)
        }
        let name = DatabaseConfiguration.trimmed(service.name)
        guard !others.contains(where: { DatabaseConfiguration.trimmed($0.name) == name }) else {
            throw DatabaseMessages.duplicateName
        }
        _ = try configuration.runtime(for: service)
    }

    private static func trimmed(_ service: DatabaseService) -> DatabaseService {
        DatabaseService(
            id: service.id, name: DatabaseConfiguration.trimmed(service.name), runtimeID: service.runtimeID,
            port: service.port)
    }
}
