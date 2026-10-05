import Foundation

/// The update archive of an appcast item and its Ed25519 signature.
public struct AppcastEnclosure: Equatable, Sendable {
    /// The HTTPS archive URL.
    public let url: URL
    /// The archive size in bytes.
    public let length: Int64
    /// The 64-byte Ed25519 signature of the archive bytes (`sparkle:edSignature`).
    public let signature: Data

    public init(url: URL, length: Int64, signature: Data) {
        self.url = url
        self.length = length
        self.signature = signature
    }
}
