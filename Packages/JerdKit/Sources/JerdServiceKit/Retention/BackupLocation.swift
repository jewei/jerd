import Foundation
import JerdFoundation

/// Where the runtime update backups of one single-instance service are.
public struct BackupLocation: Sendable {
    /// The first part of a backup ID: "mail" or "storage".
    public let key: String
    /// The name in rows: "Mail" or "Storage".
    public let displayName: String
    public let root: URL
    public let backupsDirectory: URL
    public let journalFile: URL
    public let record: RecordLocation

    public init(
        key: String, displayName: String, root: URL, backupsDirectory: URL, journalFile: URL, record: RecordLocation
    ) {
        self.key = key
        self.displayName = displayName
        self.root = root
        self.backupsDirectory = backupsDirectory
        self.journalFile = journalFile
        self.record = record
    }

    /// The Mail and Storage locations of `layout`, in the order of the Advanced page.
    public static func all(in layout: DataLayout) -> [BackupLocation] {
        let mail = layout.mail
        let storage = layout.storage
        return [
            BackupLocation(
                key: "mail", displayName: "Mail", root: mail.root, backupsDirectory: mail.runtimeBackupsDirectory,
                journalFile: mail.runtimeUpdateJournal, record: mail.record),
            BackupLocation(
                key: "storage", displayName: "Storage", root: storage.root,
                backupsDirectory: storage.runtimeBackupsDirectory, journalFile: storage.runtimeUpdateJournal,
                record: storage.record),
        ]
    }
}
