import Foundation
import JerdFoundation

/// An upstream archive with its exact size and SHA-256.
public struct PinnedArchive: Codable, Equatable, Sendable {
    /// The largest archive that a pin can name (800 MB, as for managed updates).
    public static let sizeLimit: Int64 = 800_000_000

    public let url: URL
    /// The exact size in bytes. A download stops as soon as it would exceed it.
    public let size: Int64
    public let sha256: String
    /// The reviewed GitHub release asset ID, for GitHub artifacts. Informational.
    public let assetID: Int?

    public init(url: URL, size: Int64, sha256: String, assetID: Int? = nil) {
        self.url = url
        self.size = size
        self.sha256 = sha256
        self.assetID = assetID
    }

    func validate() throws {
        guard url.scheme == "https", (1...Self.sizeLimit).contains(size), FileDigest.isSHA256Hex(sha256) else {
            throw RuntimePinCatalog.invalid("The archive pin \(url.absoluteString) is invalid.")
        }
    }
}
