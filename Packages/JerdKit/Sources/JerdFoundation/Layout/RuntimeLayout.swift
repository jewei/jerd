import Foundation

/// Paths of installed runtimes and the PHP command-line configuration.
public struct RuntimeLayout: Hashable, Sendable {
    public let root: URL

    /// Bundled development payloads: `runtimes/<installation ID>/`.
    public var developmentRuntimesDirectory: URL { root.folder("runtimes") }
    /// The selected Composer and Laravel installer paths.
    public var cliToolsFile: URL { developmentRuntimesDirectory.file("cli-tools.json") }
    public var cliConfigurationDirectory: URL { developmentRuntimesDirectory.folder("configuration") }
    public var cliINIFile: URL { cliConfigurationDirectory.file("cli.ini") }
    public var cliLocalTLSINIFile: URL { cliConfigurationDirectory.file("cli-local-tls.ini") }
    public var cliCABundleFile: URL { cliConfigurationDirectory.file("php-ca.pem") }
    public var cliEmptyINIDirectory: URL { cliConfigurationDirectory.folder("empty-ini") }
    /// The PHP inspection work folder used while the bundled payload is installed.
    public var bootstrapInspectionDirectory: URL {
        developmentRuntimesDirectory.folder("inspection").folder("empty-ini")
    }
    /// The PHP inspection work folder used during activation and import.
    public var inspectionDirectory: URL { root.folder("runtime-inspection").folder("empty-ini") }
    /// Managed builds: `runtime-updates/<kind>-<version>-<arch>-<SHA-256>/`.
    public var managedRuntimesDirectory: URL { root.folder("runtime-updates") }
    public var databaseRuntimesDirectory: URL { root.folder("database-runtimes") }
    public var mailRuntimesDirectory: URL { root.folder("mail-runtimes") }
    public var storageRuntimesDirectory: URL { root.folder("storage-runtimes") }
}
