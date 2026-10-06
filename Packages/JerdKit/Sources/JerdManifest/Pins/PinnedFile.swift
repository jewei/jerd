import Foundation
import JerdFoundation

/// A small upstream file, for example a signature or a license, with a size limit and its SHA-256.
public struct PinnedFile: Codable, Hashable, Sendable {
    public let url: URL
    /// The largest accepted size in bytes.
    public let sizeLimit: Int64
    public let sha256: String

    public init(url: URL, sizeLimit: Int64, sha256: String) {
        self.url = url
        self.sizeLimit = sizeLimit
        self.sha256 = sha256
    }

    func validate() throws {
        guard url.scheme == "https", (1...1_000_000).contains(sizeLimit), FileDigest.isSHA256Hex(sha256) else {
            throw RuntimePinCatalog.invalid("The file pin \(url.absoluteString) is invalid.")
        }
    }
}
