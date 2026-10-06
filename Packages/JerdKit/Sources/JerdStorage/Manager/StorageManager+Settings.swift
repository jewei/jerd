import JerdFoundation
import JerdServiceKit

extension StorageManager {
    /// Saves the first installed runtime with two free suggested ports. A saved runtime never
    /// changes here; a new runtime goes through `updateRuntime(_:)`.
    public func registerRuntime(_ runtime: StorageRuntime) async throws {
        try await exclusive {
            if let saved = settings.runtime {
                guard saved == runtime else { throw StorageMessages.runtimeChanged }
                return
            }
            guard runtime.isValid else { throw StorageMessages.runtimeRecordInvalid }
            var next = settings
            next.runtime = runtime
            next.ports = try await suggestPorts()
            try save(next)
            instance = makeInstance(runtime: runtime, ports: next.ports)
        }
    }

    /// The first free API port from 9000 and the first other free console port from 9001.
    public func suggestedPorts() async throws -> StoragePorts {
        guard loaded else { throw StorageMessages.notLoaded }
        return try await suggestPorts()
    }

    /// Moves stopped storage to two other free ports. A failure message is cleared.
    ///
    /// The run record is checked with the storage lock held, so a saved process that may still
    /// live blocks the change and no other Jerd process can race on the record.
    public func edit(ports: StoragePorts) async throws {
        try await exclusive {
            if let instance, await instance.processID != nil { throw StorageMessages.stopBeforeEditing }
            var next = settings
            next.ports = ports
            try next.validate()
            for port in ports.ordered { try await effects.ports.requireFree(port) }
            guard let instance, let runtime = next.runtime else { return try save(next) }
            let lease = try await instance.beginMaintenance()
            do {
                try save(next)
                try await instance.replaceDefinition(definition(runtime: runtime, ports: ports), in: lease)
            } catch {
                await instance.endMaintenance(lease)
                throw error
            }
            await instance.endMaintenance(lease)
            // No process is owned, so this only clears an earlier failure.
            try await instance.stop()
        }
    }

    func suggestPorts() async throws -> StoragePorts {
        let defaults = StorageSettings.defaultPorts
        let api = try await effects.ports.suggest(startingAt: defaults.api)
        let console = try await effects.ports.suggest(startingAt: defaults.console, excluding: [api])
        return StoragePorts(api: api, console: console)
    }
}
