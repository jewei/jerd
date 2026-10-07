import CArchive
import Foundation
import JerdFoundation

/// Reads the entries of a gzip-compressed or plain tar archive, or a zip archive, with libarchive.
///
/// Only the gzip filter and the tar and zip formats are enabled. Any warning from libarchive is
/// treated as an error. One reader belongs to one thread; it is not `Sendable`.
package final class ArchiveReader {
    /// The block size of each read from the archive file.
    package static let blockSize = 1_048_576
    /// The oldest libarchive version (3.0.0) whose read API this reader uses.
    package static let minimumLibraryVersion: Int32 = 3_000_000

    private let handle: OpaquePointer

    /// Opens `url`. Throws `cannotOpen` when libarchive cannot allocate a reader and
    /// `unreadable` when the file is not a supported archive.
    package init(_ url: URL) throws {
        try Self.requireSupportedLibrary(version: archive_version_number())
        guard let handle = archive_read_new() else { throw ArchiveFailure.cannotOpen }
        self.handle = handle
        archive_read_support_filter_gzip(handle)
        archive_read_support_format_tar(handle)
        archive_read_support_format_zip(handle)
        guard archive_read_open_filename(handle, url.path, Self.blockSize) == ARCHIVE_OK else {
            throw ArchiveFailure.unreadable
        }
    }

    deinit { archive_read_free(handle) }

    /// Refuses a system library older than the headers this module was written against.
    package static func requireSupportedLibrary(version: Int32) throws {
        guard version >= minimumLibraryVersion else { throw ArchiveFailure.libraryUnsupported }
    }

    /// The next entry header, or nil at the end of the archive.
    package func nextHeader() throws -> ArchiveEntryHeader? {
        var entry: OpaquePointer?
        let status = archive_read_next_header(handle, &entry)
        if status == ARCHIVE_EOF { return nil }
        guard status == ARCHIVE_OK, let entry, let name = archive_entry_pathname_utf8(entry) else {
            throw ArchiveFailure.invalidEntry
        }
        return ArchiveEntryHeader(
            path: String(cString: name),
            type: ArchiveEntryHeader.FileType(modeBits: UInt32(archive_entry_filetype(entry))),
            size: archive_entry_size_is_set(entry) != 0 ? archive_entry_size(entry) : nil,
            symlinkTarget: archive_entry_symlink_utf8(entry).map { String(cString: $0) },
            hardlinkTarget: archive_entry_hardlink_utf8(entry).map { String(cString: $0) },
            permissions: UInt32(archive_entry_perm(entry)),
            modificationTime: Self.modificationTime(of: entry))
    }

    private static func modificationTime(of entry: OpaquePointer) -> EntryTimestamp? {
        guard archive_entry_mtime_is_set(entry) != 0 else { return nil }
        return EntryTimestamp(
            seconds: Int64(archive_entry_mtime(entry)), nanoseconds: Int(archive_entry_mtime_nsec(entry)))
    }

    /// Reads the next data bytes of the current entry into `buffer`. Returns 0 at the end of the entry.
    package func readData(into buffer: UnsafeMutableRawBufferPointer) throws -> Int {
        let count = archive_read_data(handle, buffer.baseAddress, buffer.count)
        guard count >= 0 else { throw ArchiveFailure.damaged }
        return count
    }
}
