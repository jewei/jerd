import Darwin
import Foundation
import JerdFoundation

/// Reads `/etc/hosts` with a size limit and a clear error, never a raw Cocoa error.
public struct SystemHostsFile: HostsFileReading {
    /// The largest hosts file that the conflict check reads.
    public static let sizeLimit = 1_048_576

    private let url: URL

    public init(url: URL = URL(fileURLWithPath: "/etc/hosts")) {
        self.url = url
    }

    public func read() throws -> String {
        // The system path is a link to /private/etc/hosts, so links are followed here.
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw JerdError.unavailable("Cannot read \(url.path) (\(SystemError.describe(errno))).")
        }
        defer { close(descriptor) }
        guard let info = DescriptorIO.status(of: descriptor), info.st_mode & S_IFMT == S_IFREG,
            info.st_size <= Self.sizeLimit
        else { throw JerdError.unavailable("Cannot read \(url.path): it is not a regular file of at most 1 MiB.") }
        switch DescriptorIO.read(from: descriptor, upTo: Self.sizeLimit + 1) {
        case .success(let data):
            guard data.count <= Self.sizeLimit, let text = String(data: data, encoding: .utf8) else {
                throw JerdError.unavailable("Cannot read \(url.path) as UTF-8 text of at most 1 MiB.")
            }
            return text
        case .failure(let failure):
            throw JerdError.unavailable("Cannot read \(url.path) (\(SystemError.describe(failure.code))).")
        }
    }
}
