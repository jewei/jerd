import Foundation
import Security

/// Makes random secrets for service credentials from a cryptographic random source.
public struct SecretGenerator: Sendable {
    /// Fills the buffer with random bytes. Returns false when the source fails.
    public typealias Source = @Sendable (inout [UInt8]) -> Bool

    private let source: Source

    /// A generator with an injected source. Tests use it to simulate a failing source.
    public init(source: @escaping Source) { self.source = source }

    /// The system generator (`SecRandomCopyBytes`).
    public static let system = SecretGenerator { bytes in
        let count = bytes.count
        return bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return count == 0 }
            return SecRandomCopyBytes(kSecRandomDefault, count, base) == errSecSuccess
        }
    }

    /// `count` random bytes.
    /// - Throws: `.unavailable` when the random source fails. No partial secret is returned.
    public func bytes(_ count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        guard source(&bytes) else { throw JerdError.unavailable("Cannot create a random secret.") }
        return bytes
    }

    /// Hexadecimal text of `byteCount` random bytes (two characters per byte).
    public func hex(byteCount: Int, letterCase: HexEncoding.LetterCase = .lower) throws -> String {
        HexEncoding.string(try bytes(byteCount), letterCase: letterCase)
    }
}
