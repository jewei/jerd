import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit

/// Owns the one local Mailpit inbox, independently of sites and databases.
///
/// The shared `SingleServiceCoordinator` holds the rules that Mail and Storage share:
/// - Every call except `load` and `snapshot` requires loaded settings.
/// - One operation runs at a time. Exit detection in `snapshot()` is not an operation: it never
///   waits for a stop, so it never blocks Stop or Quit.
/// - While a runtime update needs recovery, only `load`, `start`, and `stop` run; `load` and
///   `start` recover it first.
///
/// Stop and Quit keep every captured message.
public actor MailManager {
    public nonisolated let layout: MailLayout
    nonisolated let effects: ServiceEffects
    nonisolated let coordinator: SingleServiceCoordinator<MailService>

    /// - Parameters:
    ///   - layout: the data layout; the inbox lives in `layout.mail`.
    ///   - server: the readiness answers of Mailpit. The default asks the real service.
    public init(layout: DataLayout, effects: ServiceEffects, server: (any MailServerProbing)? = nil) {
        let mail = layout.mail
        self.layout = mail
        self.effects = effects
        let server = server ?? MailServerProbe(commands: effects.commands, workingDirectory: mail.root)
        coordinator = SingleServiceCoordinator(
            service: MailService(layout: mail, dataRoot: layout.root, server: server), effects: effects,
            settings: MailSettings())
    }

    /// Loads the settings once, creates `mail/` (mode 0700), and recovers an unfinished runtime
    /// update. Later calls return the loaded settings.
    public func load() async throws -> MailSettings {
        try await coordinator.load()
    }

    /// The settings and the state. It also detects an unexpected exit of Mailpit.
    public func snapshot() async -> MailSnapshot {
        let current = await coordinator.snapshot()
        return MailSnapshot(settings: current.settings, state: current.state)
    }

    /// Saves the first installed runtime with two free suggested ports. A saved runtime never
    /// changes here; a new runtime goes through `updateRuntime(_:)`.
    public func registerRuntime(_ runtime: MailRuntime) async throws {
        try await coordinator.registerRuntime(runtime)
    }

    /// The first free SMTP port from 1025 and the first other free web port from 8025.
    public func suggestedPorts() async throws -> MailPorts {
        try await coordinator.suggestedPorts()
    }

    /// Moves a stopped inbox to two other free ports. A failure message is cleared. The run
    /// record is checked with the inbox lock held.
    public func edit(ports: MailPorts) async throws {
        try await coordinator.edit(ports: ports)
    }

    /// Recovers an unfinished runtime update, then starts Mailpit. Errors keep the kind of the
    /// failed step.
    public func start() async throws {
        try await coordinator.start()
    }

    /// Stops Mailpit gracefully, also while a runtime update needs recovery. The inbox stays.
    /// A stop that exit detection began is joined.
    public func stop() async throws {
        try await coordinator.stop()
    }

    /// Replaces the Mailpit runtime as a journaled transaction. The inbox is first checked
    /// against the saved runtime without a write. The settings and the inbox are backed up, and
    /// the backup stays until the user deletes it in Advanced.
    public func updateRuntime(_ runtime: MailRuntime) async throws {
        try await coordinator.updateRuntime(runtime)
    }

    /// Sends the test email through the local SMTP service of the running Mailpit.
    public func sendTestEmail() async throws {
        let effects = effects
        let layout = layout
        try await coordinator.exclusive { coordinator in
            guard let instance = coordinator.instance, case .running(let pid) = await instance.refresh() else {
                throw MailMessages.startBeforeTest
            }
            let ports = coordinator.settings.ports
            try await effects.ports.verifyOwnership(pid: pid, expected: Set(ports.ordered))
            let sender = TestMessageSender(commands: effects.commands, layout: layout)
            try await sender.send(TestMessage(), smtpPort: ports.smtp)
        }
    }
}
