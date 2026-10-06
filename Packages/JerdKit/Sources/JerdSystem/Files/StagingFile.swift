import Darwin
import Foundation
import JerdFoundation

/// The new bytes of a `GuardedFileSwap`, at `.jerd-hosts-<UUID>` beside the target.
///
/// `finish()` closes the file and deletes the path, unless the path holds a displaced file
/// that must stay for inspection.
final class StagingFile {
    let url: URL
    let descriptor: Int32
    /// True while the path holds the displaced original or another writer's file.
    var holdsDisplacedFile = false

    init(beside target: URL) throws {
        url = target.deletingLastPathComponent().appendingPathComponent(".jerd-hosts-\(UUID().uuidString)")
        descriptor = open(url.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw JerdError.invalid("Cannot stage the hosts file.") }
    }

    /// Writes `data`, copies the metadata of `source`, sets a new modification time, and flushes.
    ///
    /// `COPYFILE_METADATA` copies owner, group, mode, flags, ACL, extended attributes, and times.
    /// The times are then set to now, because the content is new.
    func write(_ data: Data, metadataFrom source: Int32) throws {
        guard DescriptorIO.writeAll(data, to: descriptor) == 0 else {
            throw JerdError.invalid("Cannot write the hosts update.")
        }
        guard fcopyfile(source, descriptor, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0,
            futimens(descriptor, nil) == 0, fsync(descriptor) == 0
        else { throw JerdError.invalid("Cannot preserve hosts metadata. The original file was not changed.") }
    }

    func finish() {
        close(descriptor)
        if !holdsDisplacedFile { unlink(url.path) }
    }
}
