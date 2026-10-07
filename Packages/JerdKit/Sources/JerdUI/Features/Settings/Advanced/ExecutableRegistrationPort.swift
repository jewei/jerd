import Foundation

/// Local PHP and Caddy executables. JerdLive implements it with `PHPRuntimeInspector`,
/// `CaddyRuntimeInspector`, and `SiteRegistry`. Removing a registration never deletes files.
public protocol ExecutableRegistrationPort: Sendable {
    func registrations() async throws -> LocalRuntimeRegistrations
    /// Inspects a trusted PHP CLI and its matching PHP-FPM, then registers them.
    func importPHP(cli: URL, fpm: URL) async throws
    /// Inspects a trusted Caddy 2 executable, then registers it.
    func importCaddy(_ executable: URL) async throws
    /// Removes a PHP registration. The runtime files stay on disk.
    func removePHP(_ id: UUID) async throws
    /// Makes a registered PHP runtime the default. Running sites without a pinned PHP restart.
    func setDefaultPHP(_ id: UUID) async throws
}
