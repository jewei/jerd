import Darwin
import Foundation
import JerdFoundation

/// A new private output file: created with `O_EXCL | O_NOFOLLOW`, so it never replaces or follows anything.
struct OutputFile: ~Copyable {
    private let descriptor: Int32

    /// Creates `url` with `mode`. Its parent folders are created with mode 0700 inside `root`.
    init(_ url: URL, mode: mode_t, within root: URL) throws {
        try OwnedDirectory.create(url.deletingLastPathComponent(), within: root)
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
        guard descriptor >= 0 else { throw ArchiveFailure.cannotCreateFile }
        // The umask can clear bits of the requested mode. Set the exact mode.
        guard fchmod(descriptor, mode) == 0 else {
            close(descriptor)
            throw ArchiveFailure.cannotCreateFile
        }
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }

    /// Appends `bytes`.
    func write(_ bytes: UnsafeRawBufferPointer) throws {
        guard let base = bytes.baseAddress else { return }
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw ArchiveFailure.cannotWriteFile }
            offset += count
        }
    }

    /// Sets the access and modification times to `time`. Call it after the last write, which changes them.
    func setModificationTime(_ time: EntryTimestamp) throws {
        let times = [time.timespec, time.timespec]
        guard futimens(descriptor, times) == 0 else { throw ArchiveFailure.cannotWriteFile }
    }

    /// Copies the regular file at `source` into this file in 1 MiB chunks. Returns the bytes copied.
    /// The source is opened with `O_NOFOLLOW`; it must be a regular file.
    func copyContents(of source: URL, failure: JerdError) throws -> Int64 {
        let input = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard input >= 0 else { throw failure }
        defer { close(input) }
        guard let info = DescriptorIO.status(of: input), info.st_mode & S_IFMT == S_IFREG else { throw failure }
        var buffer = [UInt8](repeating: 0, count: ArchiveReader.blockSize)
        var total: Int64 = 0
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes { Darwin.read(input, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw failure }
            if count == 0 { return total }
            try buffer.withUnsafeBytes { try write(UnsafeRawBufferPointer(rebasing: $0[0..<count])) }
            total += Int64(count)
        }
    }
}
