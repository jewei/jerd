import Foundation
import Darwin

/// The helper supplies /private/etc/hosts; tests supply a private temporary file.
/// No path is accepted from XPC requests.
public struct AtomicHostsFile: Sendable {
    public let url: URL
    public let expectedOwner: uid_t
    public init(url: URL, expectedOwner: uid_t) { self.url = url; self.expectedOwner = expectedOwner }

    public func read() throws -> Data {
        let fd = try openChecked()
        defer { close(fd) }
        return try bytes(fd)
    }

    public func replace(expected: Data, with replacement: Data) throws {
        guard replacement.count <= 1_048_576 else { throw JerdError.invalid("The hosts update is too large.") }
        let source = try openChecked()
        defer { close(source) }
        guard flock(source, LOCK_EX) == 0 else { throw JerdError.invalid("Cannot lock the hosts file.") }
        defer { flock(source, LOCK_UN) }
        guard try bytes(source) == expected else { throw JerdError.invalid("The hosts file changed. Retry the setup.") }
        var original = stat()
        guard fstat(source, &original) == 0 else { throw JerdError.invalid("Cannot inspect hosts metadata.") }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".jerd-hosts-\(UUID().uuidString)")
        let output = open(temporary.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw JerdError.invalid("Cannot stage the hosts file.") }
        defer { close(output); unlink(temporary.path) }
        try replacement.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(output, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw JerdError.invalid("Cannot write the hosts update.") }
                offset += count
            }
        }
        // Includes owner/group, mode, ACL, extended attributes, and file flags.
        guard fcopyfile(source, output, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0, fsync(output) == 0 else {
            throw JerdError.invalid("Cannot preserve hosts metadata. The original file was not changed.")
        }
        var current = stat()
        guard lstat(url.path, &current) == 0, original.st_dev == current.st_dev, original.st_ino == current.st_ino,
              original.st_ctimespec.tv_sec == current.st_ctimespec.tv_sec,
              original.st_ctimespec.tv_nsec == current.st_ctimespec.tv_nsec,
              try bytes(source) == expected else { throw JerdError.invalid("The hosts file changed during setup. Retry the operation.") }
        guard rename(temporary.path, url.path) == 0 else { throw JerdError.invalid("Cannot commit the hosts update.") }
        let directory = open(url.deletingLastPathComponent().path, O_RDONLY | O_CLOEXEC)
        if directory >= 0 { _ = fsync(directory); close(directory) }
    }

    private func openChecked() throws -> Int32 {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw JerdError.invalid("Cannot open the hosts file safely.") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == expectedOwner, info.st_nlink == 1, info.st_size <= 1_048_576 else {
            close(descriptor)
            throw JerdError.invalid("The hosts file has an unexpected type, owner, link count, or size.")
        }
        return descriptor
    }

    private func bytes(_ descriptor: Int32) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        var offset: off_t = 0
        while true {
            let count = pread(descriptor, &buffer, buffer.count, offset)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw JerdError.invalid("Cannot read the hosts file.") }
            if count == 0 { return result }
            result.append(contentsOf: buffer.prefix(count))
            guard result.count <= 1_048_576 else { throw JerdError.invalid("The hosts file is too large.") }
            offset += off_t(count)
        }
    }
}
