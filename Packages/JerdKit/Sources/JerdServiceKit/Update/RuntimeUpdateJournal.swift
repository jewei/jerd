import Foundation
import JerdFoundation

/// The undo journal of a runtime update: `runtime-update.json` in the service folder.
///
/// Compatible forms: the old `{id, names, present}` (read as version 1) and the current form with
/// `schemaVersion: 1`. Encoding is `JSONFileFormat.compact`. Recovery restores the names that the
/// journal lists, not the names of the current build, so a build that adds or reorders names
/// can still recover an older journal.
public struct RuntimeUpdateJournal: Codable, Equatable, Sendable {
    /// The only version that this build reads and writes.
    public static let currentVersion = 1
    /// The largest journal, on read.
    public static let maximumBytes = 65_535

    public let schemaVersion: Int
    /// The backup folder name under `runtime-backups/`.
    public let id: UUID
    /// The item names (directly in the service folder) that the update covers, in order.
    public let names: [String]
    /// The names that existed and were copied. A name not present did not exist before.
    public let present: [String]

    public init(id: UUID, names: [String], present: [String]) {
        schemaVersion = Self.currentVersion
        self.id = id
        self.names = names
        self.present = present
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, names, present
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentVersion
        id = try container.decode(UUID.self, forKey: .id)
        names = try container.decode([String].self, forKey: .names)
        present = try container.decode([String].self, forKey: .present)
    }

    /// True when every structural rule holds: a known version, unique safe names, and every
    /// present name listed in `names`.
    public var isValid: Bool {
        schemaVersion == Self.currentVersion && Set(names).count == names.count
            && names.allSatisfy(Self.isSafeName) && Set(present).isSubset(of: Set(names))
    }

    /// A single path component: not empty, not `.` or `..`, without `/` or a NUL byte.
    public static func isSafeName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
}
