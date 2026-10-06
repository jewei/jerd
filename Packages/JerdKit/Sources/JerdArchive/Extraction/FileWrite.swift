import Darwin
import JerdFoundation

/// One regular file to write, with its mode and the byte limit that its data must respect.
package struct FileWrite: Sendable, Equatable {
    package let path: RelativePath
    /// 0700 when the entry has any execute bit, otherwise 0600.
    package let mode: mode_t
    /// The declared size. The data must have exactly this size. Nil when the archive does not record it.
    package let declaredSize: Int64?
    /// The most bytes that the data may have.
    package let byteLimit: Int64
    /// The error when the data has more than `byteLimit` bytes.
    package let limitFailure: JerdError
    /// The entry modification time to restore after the write, or nil to keep the write time.
    package var modificationTime: EntryTimestamp? = nil
}
