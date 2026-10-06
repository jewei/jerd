import JerdFoundation
import JerdServiceKit

extension MailManager {
    /// Saves the first installed runtime with two free suggested ports. A saved runtime never
    /// changes here; a new runtime goes through `updateRuntime(_:)`.
    public func registerRuntime(_ runtime: MailRuntime) async throws {
        try await exclusive {
            if let saved = settings.runtime {
                guard saved == runtime else { throw MailMessages.runtimeChanged }
                return
            }
            guard runtime.isValid else { throw MailMessages.runtimeRecordInvalid }
            let next = MailSettings(runtime: runtime, ports: try await suggestPorts())
            try store.save(next)
            settings = next
            instance = makeInstance(runtime: runtime, ports: next.ports)
        }
    }

    /// The first free SMTP port from 1025 and the first other free web port from 8025.
    public func suggestedPorts() async throws -> MailPorts {
        guard loaded else { throw MailMessages.notLoaded }
        return try await suggestPorts()
    }

    /// Moves a stopped inbox to two other free ports. A failure message is cleared.
    ///
    /// The run record is checked with the inbox lock held, so a saved process that may still
    /// live blocks the change and no other Jerd process can race on the record.
    public func edit(ports: MailPorts) async throws {
        try await exclusive {
            if let instance, await instance.processID != nil { throw MailMessages.stopBeforeEditing }
            var next = settings
            next.ports = ports
            try next.validate()
            for port in ports.ordered { try await effects.ports.requireFree(port) }
            guard let instance, let runtime = next.runtime else {
                try store.save(next)
                settings = next
                return
            }
            let lease = try await instance.beginMaintenance()
            do {
                try store.save(next)
                settings = next
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

    func suggestPorts() async throws -> MailPorts {
        let defaults = MailSettings.defaultPorts
        let smtp = try await effects.ports.suggest(startingAt: defaults.smtp)
        let web = try await effects.ports.suggest(startingAt: defaults.web, excluding: [smtp])
        return MailPorts(smtp: smtp, web: web)
    }
}
