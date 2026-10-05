import Foundation

/// The files of one PHP-FPM master: `php/<runtime UUID>/` and its socket.
///
/// The folder is keyed by the runtime ID, so the files of a runtime stay in one place when the
/// site order changes (spec B 7.5).
public struct PoolLayout: Equatable, Hashable, Sendable {
    public let runtimeID: UUID
    /// `environment/php/<runtime UUID>/`.
    public let directory: URL
    /// The FastCGI socket in the private socket folder of the run.
    public let socket: URL

    public var configurationDirectory: URL { directory.appendingPathComponent("configuration", isDirectory: true) }
    public var fpmConfigurationFile: URL { configurationDirectory.appendingPathComponent("php-fpm.conf") }
    public var phpINIFile: URL { configurationDirectory.appendingPathComponent("php.ini") }
    public var logsDirectory: URL { directory.appendingPathComponent("logs", isDirectory: true) }
    public var logFile: URL { logsDirectory.appendingPathComponent("fpm.log") }
}
