import Foundation
import Darwin

/// Processes keep a direct append descriptor, including if the app crashes.
/// Trim in place so a live writer never continues into a renamed, unbounded file.
enum ProcessLog {
    static let limit = 8 * 1_048_576

    static func trim(_ file: URL, limit: Int = limit, prefixBytes: Int = 0) throws {
        let descriptor = open(file.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_APPEND)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1 else { throw JerdError.invalid("The process log is not an owned regular file.") }
        guard info.st_size > limit else { return }
        let headCount = min(max(0, prefixBytes), limit / 4)
        var head = [UInt8](repeating: 0, count: headCount)
        if headCount > 0 {
            guard pread(descriptor, &head, headCount, 0) == headCount else { throw JerdError.process("Cannot retain the start of the command output.") }
        }
        let count = limit / 2
        var bytes = [UInt8](repeating: 0, count: count)
        let read = pread(descriptor, &bytes, count, info.st_size - Int64(count))
        guard read == count else { throw JerdError.process("Cannot retain the end of the process log.") }
        guard ftruncate(descriptor, 0) == 0 else { throw JerdError.process("Cannot limit the process log.") }
        // Concurrent append output can appear before this retained section. Logs
        // are diagnostic only; service data never uses this truncation policy.
        try write(Data(head) + Data("[Jerd retained recent log output.]\n".utf8) + Data(bytes), to: descriptor)
    }

    static func read(_ file: URL, limit: Int = 1_048_576, tail: Bool = false) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        if tail {
            let size = try handle.seekToEnd()
            try handle.seek(toOffset: size > limit ? size - UInt64(limit) : 0)
        }
        return String(decoding: try handle.read(upToCount: limit) ?? Data(), as: UTF8.self)
    }

    private static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw JerdError.process("Cannot write the retained process log.") }
                offset += count
            }
        }
    }
}
