import Darwin
import Foundation
import JerdFoundation

/// Bounded reads of files inside the signed app bundle, which another user (for example root) may own.
package enum BundleFile {
    /// Reads a regular file of at most `limit` bytes, never through a final symbolic link.
    /// - Throws: `.unavailable` when the file is missing; `.invalid` for another type or a larger file.
    package static func read(_ url: URL, limit: Int) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw JerdError.unavailable(
                "The app bundle has no \(url.lastPathComponent) (\(SystemError.describe(errno))).")
        }
        defer { close(descriptor) }
        guard let info = DescriptorIO.status(of: descriptor), info.st_mode & S_IFMT == S_IFREG, info.st_size <= limit
        else { throw JerdError.invalid("The bundled file \(url.lastPathComponent) is invalid.") }
        switch DescriptorIO.read(from: descriptor, upTo: limit + 1) {
        case .success(let data) where data.count <= limit: return data
        case .success: throw JerdError.invalid("The bundled file \(url.lastPathComponent) is invalid.")
        case .failure(let failure):
            throw JerdError.unavailable("Cannot read \(url.path) (\(SystemError.describe(failure.code))).")
        }
    }
}
