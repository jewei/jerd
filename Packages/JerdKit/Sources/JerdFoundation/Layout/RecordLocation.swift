import Foundation

/// Where one active-run record and the lock that guards it are saved.
public struct RecordLocation: Hashable, Sendable, Identifiable, Comparable {
    public let family: RecordFamily
    /// The instance ID for families with many instances; nil for Mail and Storage.
    public let instance: UUID?
    /// The `active-run.json` (or `processes/<UUID>.json`) file.
    public let recordFile: URL
    /// The lock file that must be held to start, recover, or delete this record.
    public let lockFile: URL

    public init(family: RecordFamily, instance: UUID?, recordFile: URL, lockFile: URL) {
        self.family = family
        self.instance = instance
        self.recordFile = recordFile
        self.lockFile = lockFile
    }

    /// The stable record ID: `Mail`, `Storage`, `Database/<UUID>`, `Tunnel/<UUID>`, or `Web/<UUID>`.
    public var id: String {
        guard let instance else { return family.displayName }
        return "\(family.displayName)/\(instance.uuidString)"
    }

    /// The name of the service family, for example "Database".
    public var displayName: String { family.displayName }

    /// The folder that holds the record file.
    public var folder: URL { recordFile.deletingLastPathComponent() }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.family != rhs.family { return lhs.family < rhs.family }
        return (lhs.instance?.uuidString ?? "") < (rhs.instance?.uuidString ?? "")
    }
}
