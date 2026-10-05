import Darwin
import Foundation

/// Small, interruption-safe read and write loops on raw file descriptors.
public enum DescriptorIO {
    /// Writes every byte of `data` to `descriptor`, retrying on `EINTR`.
    /// - Returns: 0 on success, otherwise the `errno` value of the failed write.
    public static func writeAll(_ data: Data, to descriptor: Int32) -> Int32 {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return 0 }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return count < 0 ? errno : EIO }
                offset += count
            }
            return 0
        }
    }

    /// Reads from the current offset until end of file or until `limit` bytes, retrying on `EINTR`.
    /// - Returns: the bytes, or the `errno` value of the failed read.
    public static func read(from descriptor: Int32, upTo limit: Int) -> Result<Data, DescriptorIOFailure> {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: min(max(limit, 1), 1_048_576))
        while data.count < limit {
            let wanted = min(chunk.count, limit - data.count)
            let count = chunk.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, wanted) }
            if count < 0, errno == EINTR { continue }
            if count < 0 { return .failure(DescriptorIOFailure(code: errno)) }
            if count == 0 { break }
            data.append(contentsOf: chunk[0..<count])
        }
        return .success(data)
    }

    /// Reads exactly `count` bytes at `offset` without moving the file offset.
    /// - Returns: the bytes, or nil when the file is shorter or the read fails.
    public static func readExactly(from descriptor: Int32, count: Int, at offset: Int64) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        var done = 0
        while done < count {
            let result = bytes.withUnsafeMutableBytes { buffer in
                pread(descriptor, buffer.baseAddress?.advanced(by: done), count - done, offset + Int64(done))
            }
            if result < 0, errno == EINTR { continue }
            guard result > 0 else { return nil }
            done += result
        }
        return Data(bytes)
    }

    /// Returns the `fstat` result of `descriptor`, or nil when `fstat` fails.
    public static func status(of descriptor: Int32) -> stat? {
        var info = stat()
        return fstat(descriptor, &info) == 0 ? info : nil
    }

    /// True when `info` describes a regular file with one link, owned by `owner`.
    public static func isPrivateRegularFile(_ info: stat, owner: uid_t) -> Bool {
        info.st_mode & S_IFMT == S_IFREG && info.st_uid == owner && info.st_nlink == 1
    }
}
