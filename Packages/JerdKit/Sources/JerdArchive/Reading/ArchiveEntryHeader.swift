/// The header facts of one archive entry, read before its data. A pure value for the extraction plan.
package struct ArchiveEntryHeader: Sendable, Equatable {
    /// The file type bits of the entry.
    package enum FileType: Sendable, Equatable {
        case regular
        case directory
        case symbolicLink
        /// A FIFO, device, socket, or unknown type, with its raw type bits.
        case other(UInt32)

        /// Maps the `S_IFMT` bits that libarchive reports.
        package init(modeBits: UInt32) {
            switch modeBits & 0o170_000 {
            case 0o100_000: self = .regular
            case 0o040_000: self = .directory
            case 0o120_000: self = .symbolicLink
            default: self = .other(modeBits & 0o170_000)
            }
        }
    }

    /// The entry name as stored, before any check.
    package var path: String
    package var type: FileType
    /// The declared data size, or nil when the archive does not record it.
    package var size: Int64?
    /// The target of a symbolic link, relative to the entry's folder.
    package var symlinkTarget: String?
    /// The target of a hard link, relative to the archive top.
    package var hardlinkTarget: String?
    /// The permission bits (`0o7777`).
    package var permissions: UInt32
    /// The modification time, or nil when the archive does not record it.
    package var modificationTime: EntryTimestamp?

    package init(
        path: String, type: FileType, size: Int64?, symlinkTarget: String? = nil, hardlinkTarget: String? = nil,
        permissions: UInt32 = 0o644, modificationTime: EntryTimestamp? = nil
    ) {
        self.path = path
        self.type = type
        self.size = size
        self.symlinkTarget = symlinkTarget
        self.hardlinkTarget = hardlinkTarget
        self.permissions = permissions
        self.modificationTime = modificationTime
    }
}
