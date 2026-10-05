import Foundation

/// Paths of the Mailpit service folder `mail/`.
public struct MailLayout: Hashable, Sendable {
    public let root: URL

    public var settingsFile: URL { root.file(ServiceFileName.settings) }
    public var previousSettingsFile: URL { root.file(ServiceFileName.previousSettings) }
    public var lockFile: URL { root.file(ServiceFileName.lock) }
    public var activeRunFile: URL { root.file(ServiceFileName.activeRun) }
    public var logFile: URL { root.file(ServiceFileName.log) }
    public var previousLogFile: URL { root.file(ServiceFileName.previousLog) }
    /// The inbox folder `inbox/`, which holds the SQLite database and its identity markers.
    public var inboxDirectory: URL { root.folder("inbox") }
    public var inboxDatabaseFile: URL { inboxDirectory.file("messages.sqlite") }
    public var runtimeIdentityFile: URL { inboxDirectory.file(ServiceFileName.runtimeIdentity) }
    public var initializedMarkerFile: URL { inboxDirectory.file(ServiceFileName.initializedMarker) }
    public var runtimeUpdateJournal: URL { root.file(ServiceFileName.runtimeUpdateJournal) }
    public var runtimeBackupsDirectory: URL { root.folder(ServiceFileName.runtimeBackups) }

    /// A transient test message file `test-<UUID>.eml`.
    public func testMessageFile(_ id: UUID) -> URL { root.file("test-\(id.uuidString).eml") }

    /// The active-run record of the mail service.
    public var record: RecordLocation {
        RecordLocation(family: .mail, instance: nil, recordFile: activeRunFile, lockFile: lockFile)
    }
}
