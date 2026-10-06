import JerdFoundation

extension SingleServiceCoordinator {
    /// Saves the first installed runtime with free suggested ports. A saved runtime never changes
    /// here; a new runtime goes through `updateRuntime(_:)`.
    package func registerRuntime(_ runtime: Runtime) async throws {
        try await exclusive { coordinator in
            if let saved = coordinator.settings.runtime {
                guard saved == runtime else { throw coordinator.messages.runtimeChanged }
                return
            }
            guard runtime.isValid else { throw coordinator.messages.runtimeRecordInvalid }
            var next = coordinator.settings
            next.runtime = runtime
            next.ports = try await coordinator.service.suggestPorts(using: coordinator.effects.ports)
            try coordinator.save(next)
            coordinator.setInstance(coordinator.makeInstance(runtime: runtime, ports: next.ports))
        }
    }

    /// Free default ports. It changes nothing.
    package func suggestedPorts() async throws -> Ports {
        try requireLoaded()
        return try await service.suggestPorts(using: effects.ports)
    }

    /// Moves a stopped service to other free ports. A failure message is cleared.
    ///
    /// The run record is checked with the service lock held (a maintenance lease), so a saved
    /// process that may still live blocks the change and no other Jerd process can race on the
    /// record. The lease ends on every path.
    package func edit(ports: Ports) async throws {
        try await exclusive { coordinator in
            if let instance = coordinator.instance, await instance.processID != nil {
                throw coordinator.messages.stopBeforeEditing
            }
            var next = coordinator.settings
            next.ports = ports
            try next.validate()
            for port in ports.ordered { try await coordinator.effects.ports.requireFree(port) }
            guard let instance = coordinator.instance, let runtime = next.runtime else {
                return try coordinator.save(next)
            }
            let lease = try await instance.beginMaintenance()
            do {
                try coordinator.save(next)
                try await instance.replaceDefinition(
                    coordinator.service.definition(runtime: runtime, ports: ports), in: lease)
            } catch {
                await instance.endMaintenance(lease)
                throw error
            }
            await instance.endMaintenance(lease)
            // No process is owned, so this only clears an earlier failure.
            try await instance.stop()
        }
    }
}
