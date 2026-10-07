import CryptoKit
import Darwin
import Foundation

/// Streaming SHA-256 of files and data, as lowercase hexadecimal text.
public enum FileDigest {
    /// The size of each read. Cancellation is checked before each one.
    public static let chunkSize = 1_048_576

    /// SHA-256 of the file bytes followed by `suffix`.
    ///
    /// The file must be a regular file, not a symbolic link. Memory use stays at one chunk.
    public static func sha256(of url: URL, appending suffix: Data = Data()) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw JerdError.unavailable("Cannot read \(url.path) for its checksum (\(SystemError.describe(errno))).")
        }
        defer { close(descriptor) }
        guard let info = DescriptorIO.status(of: descriptor), info.st_mode & S_IFMT == S_IFREG else {
            throw JerdError.invalid("Cannot compute the checksum of \(url.path) because it is not a regular file.")
        }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            switch DescriptorIO.read(from: descriptor, upTo: chunkSize) {
            case .success(let chunk) where chunk.isEmpty:
                hasher.update(data: suffix)
                return Data(hasher.finalize())
            case .success(let chunk):
                hasher.update(data: chunk)
            case .failure(let failure):
                throw JerdError.unavailable(
                    "Cannot read \(url.path) for its checksum (\(SystemError.describe(failure.code))).")
            }
        }
    }

    /// Lowercase hexadecimal SHA-256 of a file.
    public static func hexSHA256(of url: URL) throws -> String {
        HexEncoding.string(try sha256(of: url))
    }

    /// Lowercase hexadecimal SHA-256 of bytes in memory.
    public static func hexSHA256(of data: Data) -> String {
        HexEncoding.string(SHA256.hash(data: data))
    }

    /// True when `text` is a SHA-256 digest in lowercase hexadecimal (64 characters `0-9`, `a-f`).
    public static func isSHA256Hex(_ text: String) -> Bool {
        HexEncoding.isHex(text, length: 64)
    }
}
