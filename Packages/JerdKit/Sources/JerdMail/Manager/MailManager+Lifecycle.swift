import JerdFoundation
import JerdServiceKit

extension MailManager {
    /// Recovers an unfinished runtime update, then starts Mailpit. Errors keep the kind of the
    /// failed step.
    public func start() async throws {
        try await exclusive(allowingRecovery: true) {
            guard let instance, settings.runtime != nil else { throw MailMessages.runtimeMissing }
            try await recoverPendingUpdate()
            try await instance.start()
        }
    }

    /// Stops Mailpit gracefully, also while a runtime update needs recovery. The inbox stays.
    /// A stop that exit detection began is joined.
    public func stop() async throws {
        try await exclusive(allowingRecovery: true) {
            try await instance?.stop()
        }
    }

    /// Sends the test email through the local SMTP service of the running Mailpit.
    public func sendTestEmail() async throws {
        try await exclusive {
            guard let instance, case .running(let pid) = await instance.refresh() else {
                throw MailMessages.startBeforeTest
            }
            try await effects.ports.verifyOwnership(pid: pid, expected: Set(settings.ports.ordered))
            let sender = TestMessageSender(commands: effects.commands, layout: layout)
            try await sender.send(TestMessage(), smtpPort: settings.smtpPort)
        }
    }
}
