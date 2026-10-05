import Foundation

/// One runtime update backup in Advanced, or one service whose backups cannot be inspected.
public struct RetainedBackup: Identifiable, Equatable, Sendable {
    /// `<service>/<UUID>` for a backup (the ID that `remove` takes), or `<service>` for a row that
    /// reports a problem with the whole service folder.
    public let id: String
    /// "Mail" or "Storage".
    public let service: String
    public let directory: URL
    /// The logical size, or nil when it is unknown.
    public let bytes: Int64?
    public let detail: String
    /// True when the backup must not be deleted now.
    public let isProtected: Bool

    public init(id: String, service: String, directory: URL, bytes: Int64?, detail: String, isProtected: Bool) {
        self.id = id
        self.service = service
        self.directory = directory
        self.bytes = bytes
        self.detail = detail
        self.isProtected = isProtected
    }
}
