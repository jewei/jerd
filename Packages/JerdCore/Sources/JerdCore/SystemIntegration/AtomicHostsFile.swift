import Foundation
import Darwin

/// The helper supplies /private/etc/hosts; tests supply a private temporary file.
/// No path is accepted from XPC requests.
public struct AtomicHostsFile: Sendable {
    public let url: URL
    public let expectedOwner: uid_t
    private let preExchange: (@Sendable () throws -> Void)?
    private let preRestore: (@Sendable () throws -> Void)?
    public init(url: URL, expectedOwner: uid_t) {
        self.url = url; self.expectedOwner = expectedOwner; self.preExchange = nil; self.preRestore = nil
    }
    init(url: URL, expectedOwner: uid_t, preExchange: @escaping @Sendable () throws -> Void,
         preRestore: (@Sendable () throws -> Void)? = nil) {
        self.url = url; self.expectedOwner = expectedOwner
        self.preExchange = preExchange; self.preRestore = preRestore
    }

    public func read() throws -> Data {
        let fd = try openChecked(url)
        defer { close(fd) }
        return try bytes(fd)
    }

    public func replace(expected: Data, with replacement: Data) throws {
        guard replacement.count <= 1_048_576 else { throw JerdError.invalid("The hosts update is too large.") }
        let source = try openChecked(url)
        defer { close(source) }
        guard flock(source, LOCK_EX) == 0 else { throw JerdError.invalid("Cannot lock the hosts file.") }
        defer { flock(source, LOCK_UN) }
        guard try bytes(source) == expected else { throw JerdError.invalid("The hosts file changed. Retry the setup.") }
        let original = try metadata(source)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".jerd-hosts-\(UUID().uuidString)")
        let output = open(temporary.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard output >= 0 else { throw JerdError.invalid("Cannot stage the hosts file.") }
        var temporaryContainsDisplacedDestination = false
        defer {
            close(output)
            if !temporaryContainsDisplacedDestination { unlink(temporary.path) }
        }
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
        guard lstat(url.path, &current) == 0, original.info.st_dev == current.st_dev, original.info.st_ino == current.st_ino,
              try metadata(source).matches(original, includingChangeTime: true),
              try bytes(source) == expected else { throw JerdError.invalid("The hosts file changed during setup. Retry the operation.") }
        let staged = try metadata(output)
        try preExchange?()
        guard renamex_np(temporary.path, url.path, UInt32(RENAME_SWAP)) == 0 else {
            throw JerdError.invalid("Cannot commit the hosts update.")
        }
        temporaryContainsDisplacedDestination = true
        defer {
            let directory = open(url.deletingLastPathComponent().path, O_RDONLY | O_CLOEXEC)
            if directory >= 0 { _ = fsync(directory); close(directory) }
        }
        guard matches(temporary, metadata: original, content: expected) else {
            let recovery = "The hosts file changed during setup. A displaced file is preserved at \(temporary.path). Inspect it before recovery."
            // Do not knowingly replace another writer's later destination.
            guard matches(url, metadata: staged, content: replacement) else {
                throw JerdError.partialChange(recovery)
            }
            do { try preRestore?() }
            catch { throw JerdError.partialChange(recovery) }
            guard renamex_np(temporary.path, url.path, UInt32(RENAME_SWAP)) == 0 else {
                throw JerdError.partialChange(recovery)
            }
            // A writer can race even the restoration exchange. Delete only our
            // unchanged staging inode; preserve any later file and the journal.
            guard matches(temporary, metadata: staged, content: replacement) else {
                throw JerdError.partialChange(recovery)
            }
            temporaryContainsDisplacedDestination = false
            throw JerdError.invalid("The hosts file changed during setup. Retry the operation.")
        }
        temporaryContainsDisplacedDestination = false
        _ = unlink(temporary.path)
    }

    private func openChecked(_ path: URL) throws -> Int32 {
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw JerdError.invalid("Cannot open the hosts file safely.") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == expectedOwner, info.st_nlink == 1, info.st_size <= 1_048_576 else {
            close(descriptor)
            throw JerdError.invalid("The hosts file has an unexpected type, owner, link count, or size.")
        }
        return descriptor
    }

    private func matches(_ path: URL, metadata expected: Metadata, content: Data) -> Bool {
        guard let descriptor = try? openChecked(path) else { return false }
        defer { close(descriptor) }
        return (try? metadata(descriptor).matches(expected)) == true && (try? bytes(descriptor)) == content
    }

    private struct Metadata {
        let info: stat
        let acl: Data
        let attributes: [String: Data]

        func matches(_ other: Self, includingChangeTime: Bool = false) -> Bool {
            let rhs = other.info
            // Exchange changes ctime, so compare the actual metadata after it.
            return info.st_dev == rhs.st_dev && info.st_ino == rhs.st_ino
                && info.st_mode == rhs.st_mode && info.st_uid == rhs.st_uid && info.st_gid == rhs.st_gid
                && info.st_nlink == rhs.st_nlink && info.st_flags == rhs.st_flags && info.st_size == rhs.st_size
                && info.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec && info.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
                && (!includingChangeTime || (info.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
                    && info.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec))
                && acl == other.acl && attributes == other.attributes
        }
    }

    private func metadata(_ descriptor: Int32) throws -> Metadata {
        let failure = JerdError.invalid("Cannot inspect hosts metadata safely.")
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw failure }
        var aclData = Data()
        if let acl = acl_get_fd(descriptor) {
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            var length: ssize_t = 0
            guard let text = acl_to_text(acl, &length) else { throw failure }
            defer { acl_free(text) }
            guard (0...1_048_576).contains(length) else { throw failure }
            aclData = Data(bytes: text, count: length)
        } else if errno != ENOENT { throw failure }
        let length = flistxattr(descriptor, nil, 0, 0)
        guard (0...1_048_576).contains(length) else { throw failure }
        var names = [CChar](repeating: 0, count: length)
        if length > 0 {
            guard flistxattr(descriptor, &names, names.count, 0) == length else { throw failure }
        }
        var attributes: [String: Data] = [:]
        var remaining = 1_048_576 - length - aclData.count
        for name in names.split(separator: 0) {
            let key = String(decoding: name.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let count = fgetxattr(descriptor, key, nil, 0, 0, 0)
            guard count >= 0 && count <= remaining else { throw failure }
            var value = Data(count: count)
            let read = value.withUnsafeMutableBytes { fgetxattr(descriptor, key, $0.baseAddress, count, 0, 0) }
            guard read == count else { throw failure }
            attributes[key] = value
            remaining -= count
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              info.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              info.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw failure }
        return Metadata(info: info, acl: aclData, attributes: attributes)
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
