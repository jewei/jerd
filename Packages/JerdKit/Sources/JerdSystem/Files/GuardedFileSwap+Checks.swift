import Darwin
import Foundation
import JerdFoundation

extension GuardedFileSwap {
    /// Opens `path` read-only without following a link and without blocking on a FIFO. The file must be
    /// a regular file of the expected owner, with one link, and at most `maximumSize` bytes.
    func openChecked(_ path: URL) throws -> Int32 {
        let descriptor = open(path.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw JerdError.invalid("Cannot open the hosts file safely.") }
        guard let info = DescriptorIO.status(of: descriptor),
            DescriptorIO.isPrivateRegularFile(info, owner: expectedOwner), info.st_size <= Self.maximumSize
        else {
            close(descriptor)
            throw JerdError.invalid("The hosts file has an unexpected type, owner, link count, or size.")
        }
        return descriptor
    }

    /// All bytes from offset 0, without moving the file offset.
    func bytes(_ descriptor: Int32) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                pread(descriptor, $0.baseAddress, $0.count, off_t(result.count))
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw JerdError.invalid("Cannot read the hosts file.") }
            if count == 0 { return result }
            result.append(contentsOf: buffer[0..<count])
            guard result.count <= Self.maximumSize else { throw JerdError.invalid("The hosts file is too large.") }
        }
    }

    /// True when `path` passes `openChecked` and has this metadata (without change time) and content.
    func matches(_ path: URL, metadata expected: FileMetadataSnapshot, content: Data) -> Bool {
        guard let descriptor = try? openChecked(path) else { return false }
        defer { close(descriptor) }
        guard let snapshot = try? FileMetadataSnapshot.capture(descriptor), snapshot.matches(expected),
            let current = try? bytes(descriptor)
        else { return false }
        return current == content
    }

    /// Takes the exclusive advisory lock without blocking the helper. It retries until `lockTimeout`.
    func lock(_ descriptor: Int32) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: lockTimeout)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR else {
                throw JerdError.invalid("Cannot lock the hosts file.")
            }
            guard clock.now < deadline else {
                throw JerdError.locked("Another process holds a lock on the hosts file. Close it, then retry.")
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
