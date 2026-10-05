import Foundation

/// Paths of one database instance folder `databases/instances/<UUID>/`.
public struct DatabaseInstanceLayout: Hashable, Sendable {
    public let id: UUID
    public let root: URL

    public var lockFile: URL { root.file(ServiceFileName.lock) }
    public var activeRunFile: URL { root.file(ServiceFileName.activeRun) }
    public var runtimeIdentityFile: URL { root.file(ServiceFileName.runtimeIdentity) }
    public var initializedMarkerFile: URL { root.file(ServiceFileName.initializedMarker) }
    /// `{"password": "<64 lowercase hex>"}`.
    public var credentialsFile: URL { root.file(ServiceFileName.credentials) }
    /// The registration kept after Remove, for Restore.
    public var removedRegistrationFile: URL { root.file("removed-registration.json") }
    public var logFile: URL { root.file(ServiceFileName.log) }
    public var previousLogFile: URL { root.file(ServiceFileName.previousLog) }
    public var dataDirectory: URL { root.folder(ServiceFileName.data) }

    /// A file in the instance folder, for engine files such as `client.cnf` or `redis.conf`.
    public func file(named name: String) -> URL { root.file(name) }

    /// The active-run record of this instance.
    public var record: RecordLocation {
        RecordLocation(family: .database, instance: id, recordFile: activeRunFile, lockFile: lockFile)
    }
}
