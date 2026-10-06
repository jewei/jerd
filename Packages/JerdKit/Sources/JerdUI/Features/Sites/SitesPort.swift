import Foundation
import JerdWeb

/// The web sites and their HTTPS setup, as the Sites section needs them. JerdLive implements it
/// with `SiteChangeTransaction`, `EnvironmentCoordinator`, `SystemSetupGateway`,
/// `ProjectDetector`, and the helper client. Every change goes through one site transaction.
public protocol SitesPort: Sendable {
    /// The saved sites and runtimes.
    /// - Throws: When the file cannot be read. The file stays as it is.
    func loadConfiguration() async throws -> AppConfiguration
    /// The state of PHP-FPM and Caddy, and the sites that they serve.
    func environment() async -> EnvironmentSnapshot
    /// The approved HTTPS setup that the helper reports. An absent setup is an empty status.
    func setupStatus() async throws -> HTTPSSetupStatus
    /// The local CA of this installation (`SystemSetupGateway.localAuthority`), or nil before it
    /// is prepared. A hostname counts as approved only for this CA (`ApprovalPredicate.approves`).
    /// - Throws: When the CA files are corrupt. They stay in place.
    func localAuthority() async throws -> InstallationAuthority?
    /// Saves one edit. A running environment follows it; a new site starts when
    /// `startIfStopped` is true.
    func apply(_ change: SiteChange, startIfStopped: Bool) async throws -> SiteChangeOutcome
    /// Serves exactly these enabled sites. An empty set stops every site.
    func run(_ siteIDs: Set<UUID>) async throws -> SiteChangeOutcome
    /// Registers the helper, applies the approved setup, and continues the waiting change.
    /// `HTTPSApproval.id` is new for each waiting change; `HTTPSSetup.id` is the installation ID
    /// and the same for every approval, so the port keeps its own table by approval ID. The
    /// removed hostnames are the approved hostnames that the waiting change no longer serves.
    func approve(_ approval: HTTPSApproval) async throws -> AppConfiguration
    /// Forgets a change that waits for approval. Nothing was saved or stopped for it.
    func discard(_ approval: HTTPSApproval) async
    /// Ends the current site change at its next step. Nothing new starts from it.
    func requestStop() async
    /// Stops PHP-FPM and Caddy, after `requestStop()`.
    func stopEnvironment() async throws
    /// The document root that the project files suggest. It reads file metadata only.
    func suggestDocumentRoot(projectPath: String) async throws -> DocumentRootSuggestion
    /// The folder of the web logs, or nil when no log exists yet.
    func environmentLogs() async -> URL?
    /// Stops the sites and registers the helper again. macOS can ask for approval.
    func reconnectHelper() async throws
    /// Stops the sites, removes the host entries and the CA trust, and unregisters the helper.
    func removeSystemSetup() async throws
    /// Opens Login Items & Extensions in System Settings, where the user allows the helper.
    func openLoginItems() async
}
