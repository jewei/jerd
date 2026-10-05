import Darwin
import Foundation
import JerdFoundation

/// A bounded process log: one private file that a child appends to, trimmed in place.
///
/// Trimming keeps the same inode, so a child that still holds an append descriptor (also after a
/// Jerd crash) keeps writing into the bounded file. Bytes written during a trim can be lost or
/// appear before the retained part; logs are diagnostics, never service data.
public struct ProcessLogFile: Hashable, Sendable {
    /// A log above this size is trimmed (8 MiB).
    public static let defaultThreshold = 8 * 1_048_576
    /// The head that command logs keep for output parsers (1 MiB).
    public static let commandHeadBytes = 1_048_576
    /// The line between the retained head and the retained tail.
    public static let marker = "[Jerd retained recent log output.]\n"

    public let url: URL
    /// The size above which `trim()` acts.
    public let threshold: Int
    /// The bytes kept from the start of the file, at most a quarter of the threshold.
    public let retainedHeadBytes: Int

    public init(url: URL, retainedHeadBytes: Int = 0, threshold: Int = defaultThreshold) {
        self.url = url
        self.threshold = max(threshold, 4)
        self.retainedHeadBytes = min(max(0, retainedHeadBytes), self.threshold / 4)
    }

    /// The bytes kept from the end of the file: half of the threshold (4 MiB by default).
    public var retainedTailBytes: Int { threshold / 2 }

    /// Replaces any old log with an empty private file and opens it for appending.
    public func create() throws -> FileHandle {
        try AtomicFile.write(Data(), to: url, durability: .standard)
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw JerdError.processFailed("Cannot open process log: \(url.path)") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard let info = DescriptorIO.status(of: descriptor), DescriptorIO.isPrivateRegularFile(info, owner: geteuid())
        else { throw notOwned }
        return handle
    }

    /// Trims the log in place when it is above the threshold. A missing log is not an error.
    /// - Returns: true when the file was trimmed.
    @discardableResult
    public func trim() throws -> Bool {
        guard let handle = try openOwned(O_RDWR | O_APPEND) else { return false }
        let descriptor = handle.fileDescriptor
        guard let info = DescriptorIO.status(of: descriptor), info.st_size > threshold else { return false }
        var head = Data()
        if retainedHeadBytes > 0 {
            guard let bytes = DescriptorIO.readExactly(from: descriptor, count: retainedHeadBytes, at: 0) else {
                throw JerdError.processFailed("Cannot retain the start of the command output.")
            }
            head = bytes
        }
        let tailOffset = info.st_size - Int64(retainedTailBytes)
        guard let tail = DescriptorIO.readExactly(from: descriptor, count: retainedTailBytes, at: tailOffset) else {
            throw JerdError.processFailed("Cannot retain the end of the process log.")
        }
        guard ftruncate(descriptor, 0) == 0 else { throw JerdError.processFailed("Cannot limit the process log.") }
        guard DescriptorIO.writeAll(head + Data(Self.marker.utf8) + tail, to: descriptor) == 0 else {
            throw JerdError.processFailed("Cannot write the retained process log.")
        }
        return true
    }

    /// The first `limit` bytes, decoded as UTF-8 (invalid sequences become U+FFFD). Missing → "".
    public func readHead(limit: Int) throws -> String {
        guard let handle = try openOwned(O_RDONLY) else { return "" }
        return try decode(DescriptorIO.read(from: handle.fileDescriptor, upTo: limit))
    }

    /// The last `limit` bytes, decoded as UTF-8 (invalid sequences become U+FFFD). Missing → "".
    public func readTail(limit: Int) throws -> String {
        guard let handle = try openOwned(O_RDONLY) else { return "" }
        let size = DescriptorIO.status(of: handle.fileDescriptor)?.st_size ?? 0
        lseek(handle.fileDescriptor, max(0, size - Int64(limit)), SEEK_SET)
        return try decode(DescriptorIO.read(from: handle.fileDescriptor, upTo: limit))
    }

    /// Trims the log and renames it to `previous`, for example `server.previous.log`.
    public func rotate(to previous: URL) throws {
        try trim()
        guard rename(url.path, previous.path) == 0 || errno == ENOENT else {
            throw JerdError.unavailable("Cannot keep the previous process log (\(SystemError.describe(errno))).")
        }
    }

    /// Opens the log without following a link. Nil when it does not exist.
    private func openOwned(_ flags: Int32) throws -> FileHandle? {
        let descriptor = open(url.path, flags | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            let code = errno
            if code == ENOENT { return nil }
            if code == ELOOP { throw notOwned }
            throw JerdError.unavailable("Cannot open \(url.path) (\(SystemError.describe(code))).")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        guard let info = DescriptorIO.status(of: descriptor), DescriptorIO.isPrivateRegularFile(info, owner: geteuid())
        else { throw notOwned }
        return handle
    }

    private func decode(_ result: Result<Data, DescriptorIOFailure>) throws -> String {
        switch result {
        case .success(let data): return String(decoding: data, as: UTF8.self)
        case .failure(let failure):
            throw JerdError.unavailable("Cannot read \(url.path) (\(SystemError.describe(failure.code))).")
        }
    }

    private var notOwned: JerdError { .invalid("The process log is not an owned regular file: \(url.path)") }
}
