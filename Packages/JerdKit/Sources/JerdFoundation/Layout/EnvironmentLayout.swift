import Foundation

/// Paths of the web environment folder `environment/` (Caddy, PHP-FPM, the installation CA).
public struct EnvironmentLayout: Hashable, Sendable {
    public let root: URL

    /// The stable installation ID: an uppercase UUID string without a newline.
    public var installationIDFile: URL { root.file("installation-id") }
    public var configurationDirectory: URL { root.folder("configuration") }
    public var caddyConfigurationFile: URL { configurationDirectory.file("caddy.json") }
    /// Legacy layout only: the pool file that old builds wrote for their first PHP runtime. Every
    /// pool now lives in `phpRuntimeDirectory(_:)`. JerdWeb only removes this file.
    public var fpmConfigurationFile: URL { configurationDirectory.file("php-fpm.conf") }
    /// Legacy layout only: the FPM `php.ini` of the old first pool. JerdWeb only removes this file.
    public var phpINIFile: URL { configurationDirectory.file("php.ini") }
    /// Legacy layout only: the configuration with which earlier builds let Caddy make the CA.
    /// Jerd now makes the CA itself and no longer writes this file.
    public var prepareCAFile: URL { configurationDirectory.file("prepare-ca.json") }
    public var phpCABundleFile: URL { configurationDirectory.file("php-ca.pem") }
    public var emptyINIDirectory: URL { configurationDirectory.folder("empty-ini") }
    /// Caddy file-system storage (`XDG_DATA_HOME`), which holds the installation CA.
    public var certificatesDirectory: URL { root.folder("certificates") }
    /// The ID of the CA that Caddy made for earlier builds.
    public static let legacyAuthorityID = "jerd"
    /// The ID of the CA that Jerd makes, limited to `.test` names.
    public static let constrainedAuthorityID = "jerd-2"

    /// The folder of one CA in Caddy's storage: `pki/authorities/<id>/`.
    public func authorityDirectory(_ id: String) -> URL {
        certificatesDirectory.folder("pki").folder("authorities").folder(id)
    }
    /// The CA that Caddy made (`jerd`). An installation that has it keeps it until it migrates.
    public var legacyRootCertificateFile: URL { authorityDirectory(Self.legacyAuthorityID).file("root.crt") }
    /// The CA that Jerd makes (`jerd-2`), which may sign only `.test` names. Caddy loads it.
    public var constrainedRootCertificateFile: URL { authorityDirectory(Self.constrainedAuthorityID).file("root.crt") }
    /// The private key of the constrained CA (mode 0600). Only Caddy and the provisioner read it.
    public var constrainedRootKeyFile: URL { authorityDirectory(Self.constrainedAuthorityID).file("root.key") }
    public var logsDirectory: URL { root.folder("logs") }
    public var caddyLogFile: URL { logsDirectory.file("caddy.log") }
    /// Legacy layout only: the log of the old first pool. JerdWeb only removes this file.
    public var fpmLogFile: URL { logsDirectory.file("fpm.log") }
    /// The process records of the web environment.
    public var processesDirectory: URL { root.folder("processes") }
    /// The lock that the serving engine and recovery hold while they use web records.
    public var recoveryLockFile: URL { processesDirectory.file("recovery.lock") }

    /// The folder of the FPM pool of one PHP runtime: `php/<runtime UUID>/`. Every runtime has one.
    public func phpRuntimeDirectory(_ runtimeID: UUID) -> URL { root.folder("php").folder(runtimeID.uuidString) }

    /// A transient preflight folder `preflight-<UUID>/`, deleted after use.
    public func preflightDirectory(_ id: UUID) -> URL { root.folder("preflight-\(id.uuidString)") }

    /// The record of one supervised web process, named by its supervisor token.
    public func processRecord(_ token: UUID) -> RecordLocation {
        RecordLocation(
            family: .web, instance: token, recordFile: processesDirectory.file("\(token.uuidString).json"),
            lockFile: recoveryLockFile)
    }
}
