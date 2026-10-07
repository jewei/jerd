import Foundation

/// Paths of one tunnel connector folder `tunnels/instances/<UUID>/`.
public struct TunnelInstanceLayout: Hashable, Sendable {
    public let id: UUID
    public let root: URL

    public var lockFile: URL { root.file(ServiceFileName.lock) }
    public var activeRunFile: URL { root.file(ServiceFileName.activeRun) }
    /// The empty cloudflared configuration (`{}` and a newline).
    public var configurationFile: URL { root.file("config.yml") }
    /// `server.log`: the output of the current connector run.
    public var logFile: URL { root.file(ServiceFileName.log) }
    /// `server.previous.log`: the output of earlier connector runs (at most 4 MiB).
    public var previousLogFile: URL { root.file(ServiceFileName.previousLog) }
    /// The private `HOME` of the connector process.
    public var homeDirectory: URL { root.folder("home") }

    /// The active-run record of this connector.
    public var record: RecordLocation {
        RecordLocation(family: .tunnel, instance: id, recordFile: activeRunFile, lockFile: lockFile)
    }
}
