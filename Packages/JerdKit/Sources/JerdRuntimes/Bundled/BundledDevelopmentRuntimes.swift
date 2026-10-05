/// The installed development group: PHP (CLI and FPM), Caddy, Composer, and the Laravel installer.
///
/// JerdWeb inspects PHP and Caddy and turns them into site configuration records.
public struct BundledDevelopmentRuntimes: Sendable {
    /// `executable` is the CLI, `secondaryExecutable` is PHP-FPM.
    public let php: InstalledPayload
    public let caddy: InstalledPayload
    public let composer: InstalledPayload
    public let laravel: InstalledPayload
    /// The CLI tool record after the merge of rule B7.
    public let companions: CLICompanions
}
