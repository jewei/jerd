import JerdMail
import JerdRuntimes

/// The local Mailpit inbox. JerdLive implements it with `MailManager`; the live `load()` installs
/// an embedded Mailpit when no runtime is saved. An app that installs Mailpit on demand downloads
/// nothing at load: `installRuntime` runs only after a user action.
public protocol MailPort: Sendable {
    /// Reads `mail/settings.json` once and returns the first snapshot.
    /// - Throws: when the settings cannot be read. The file stays as it is.
    func load() async throws -> MailSnapshot
    /// Why the setup of the bundled Mailpit in the last `load()` failed, or nil. The load stays
    /// usable without it; the page shows this reason with the way to install it.
    func runtimeSetupFailure() async -> String?
    /// The pinned Mailpit that Jerd can install on demand, or nil when the app has no such pin.
    func runtimeOffer() async -> ServiceRuntimeOffer?
    /// Installs the pinned Mailpit (reuse, free space, download, checks, preparation) and registers
    /// it, which chooses the ports. It never touches the inbox. Cancellation stops it before its
    /// final rename.
    func installRuntime(
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> MailRuntime
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
