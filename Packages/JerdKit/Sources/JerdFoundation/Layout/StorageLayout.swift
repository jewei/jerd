import Foundation

/// Paths of the RustFS service folder `storage/`.
public struct StorageLayout: Hashable, Sendable {
    public let root: URL

    public var settingsFile: URL { root.file(ServiceFileName.settings) }
    public var previousSettingsFile: URL { root.file(ServiceFileName.previousSettings) }
    public var lockFile: URL { root.file(ServiceFileName.lock) }
    public var activeRunFile: URL { root.file(ServiceFileName.activeRun) }
    public var logFile: URL { root.file(ServiceFileName.log) }
    public var previousLogFile: URL { root.file(ServiceFileName.previousLog) }
    public var runtimeIdentityFile: URL { root.file(ServiceFileName.runtimeIdentity) }
    public var initializedMarkerFile: URL { root.file(ServiceFileName.initializedMarker) }
    /// `credentials.json`. Its exact bytes are hashed in `initialized.json`; never re-encode it.
    public var credentialsFile: URL { root.file(ServiceFileName.credentials) }
    /// The raw access key text, without a newline.
    public var accessKeyFile: URL { root.file("access-key") }
    /// The raw secret key text, without a newline.
    public var secretKeyFile: URL { root.file("secret-key") }
    public var dataDirectory: URL { root.folder(ServiceFileName.data) }
    /// The RustFS volume format file, hashed in `initialized.json`.
    public var formatFile: URL { dataDirectory.folder(".rustfs.sys").file("format.json") }
    public var runtimeUpdateJournal: URL { root.file(ServiceFileName.runtimeUpdateJournal) }
    public var runtimeBackupsDirectory: URL { root.folder(ServiceFileName.runtimeBackups) }

    /// The active-run record of the storage service.
    public var record: RecordLocation {
        RecordLocation(family: .storage, instance: nil, recordFile: activeRunFile, lockFile: lockFile)
    }
}
