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
    public var prepareCAFile: URL { configurationDirectory.file("prepare-ca.json") }
    public var phpCABundleFile: URL { configurationDirectory.file("php-ca.pem") }
    public var emptyINIDirectory: URL { configurationDirectory.folder("empty-ini") }
    /// Caddy file-system storage (`XDG_DATA_HOME`), which holds the installation CA.
    public var certificatesDirectory: URL { root.folder("certificates") }
    public var rootCertificateFile: URL {
        certificatesDirectory.folder("pki").folder("authorities").folder("jerd").file("root.crt")
    }
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
