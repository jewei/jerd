import JerdMail

/// The local Mailpit inbox. JerdLive implements it with `MailManager`; the live `load()` first
/// installs the bundled Mailpit when no runtime is saved.
public protocol MailPort: Sendable {
    /// Reads `mail/settings.json` once and returns the first snapshot.
    /// - Throws: when the settings cannot be read. The file stays as it is.
    func load() async throws -> MailSnapshot
    /// The settings and the state. It also detects an unexpected exit.
    func snapshot() async -> MailSnapshot
    /// The inbox folder and the server log.
    func files() async -> ServiceFiles
    func start() async throws
    /// Stops gracefully. The inbox stays. A timeout leaves the service `stuck`.
    func stop() async throws
    func sendTestEmail() async throws
    /// The first free SMTP port from 1025 and the first other free web port from 8025.
    func suggestedPorts() async throws -> MailPorts
    /// Moves the stopped inbox to two other free ports.
    func edit(ports: MailPorts) async throws
}
