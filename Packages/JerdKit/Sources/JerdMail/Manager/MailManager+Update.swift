import JerdFoundation
import JerdServiceKit

extension MailManager {
    /// Replaces the Mailpit runtime as a journaled transaction (see `RuntimeUpdateTransaction`).
    ///
    /// The inbox is first checked against the saved runtime without a write. Then the settings,
    /// the inbox, and both markers are backed up, the new runtime must pass a full start, and a
    /// stopped inbox is stopped again. A failure restores the backup and restarts the previous
    /// runtime when it ran. The backup stays until the user deletes it in Advanced.
    public func updateRuntime(_ runtime: MailRuntime) async throws {
        try await exclusive {
            guard let previous = settings.runtime, let instance else { throw MailMessages.runtimeMissing }
            guard runtime != previous else { return }
            guard runtime.isValid else { throw MailMessages.runtimeRecordInvalid }
            var updated = settings
            updated.runtime = runtime
            let next = updated
            let inbox = MailInbox(layout: layout)
            let steps = RuntimeUpdateSteps(
                validatePrevious: { try inbox.validate(for: previous) },
                apply: { try await self.adopt(next, replacing: previous) },
                reloadAfterRestore: { try await self.reloadDefinition() })
            try await transaction.run(
                on: instance, to: definition(runtime: runtime, ports: next.ports), steps: steps)
        }
    }

    /// Saves `next` with its new runtime and moves the saved inbox markers to it.
    private func adopt(_ next: MailSettings, replacing previous: MailRuntime) throws {
        guard let runtime = next.runtime else { throw MailMessages.runtimeMissing }
        try store.save(next, replacing: previous)
        settings = next
        try MailInbox(layout: layout).adopt(runtime)
    }
}
