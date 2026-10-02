import Foundation
import CryptoKit
import Security

/// A restricted OpenPGP v4 verifier for Oracle's pinned RSA build key.
/// Accepts binary-document signatures with RSA and SHA-256 only (RFC 4880).
enum MySQLSignature {
    static let fingerprint = "BCA43417C3B485DD128EC6D4B7B3B788A8D3785C"
    // PKCS#1 public key from RPM-GPG-KEY-mysql-2025, SHA-256:
    // a4bcd9f16a53cc763f87b9955dbcdced33c7aa90296b157eb6ceef0f156f4327
    private static let publicKey = "MIICCgKCAgEAkoubdJy+vx493dD8LG3Z22Pkqi1CGd7lmUJurbDYb052obzz2QRnZffYlmE7dipl6dCnjdrPaZiypBgG2nED9UaszBZ6B2sEjH9Kk1FYwL4ZyOPqszA40zUgavX2t5x5jmMaMJ560ZKYkFDP8g+/yZlRDYMFm+mpGXhmK13IfY3eF1d7fDg+kxs03nU5ItEwza+mGWIQu41JvXyvWbNvfaczl0sUUTRnftx/YG14s6wbuC/95VKzX//6zOzr1fR6O7vWGMgENy9/jgASvRShzYa6YvENHG4b1pA+KAiifmGeeF6zhtGE4P2FALOf9//xQEyNbFnbS4yeaUm9KJ1dyyG2q0UzfJQuC3v+ZHd5XKLfSfG9xDFy+afThlu8AX5jVUUlCO+FZsLfr/YMqdB3dJHkQlJ/JaP9VdGA/YvdirBPvyKqGE458mv+ZF+NYwfL69Xm5BxbieNOPhuhE3dKMMMauuIyyHLKfxgWRxlNESigKPQ0Sx+66UOz1ZZ8PEwzZTrVreRCZQVxXDy/jYFm6pAAwMgP10jXlpaqJ7z5WH5mrJwBwKTHfTYT0IQu4SU4wogMBvFMlqVfA49OwxxUOcQW5E5yh9jqybYLj6kjWLUwEm7Fs9PUvLo6Ew1xU9ezWxTNnTCIqtGuFUAd0sx9dx9oqPQm4P08yayRpsIKF4MCAwEAAQ=="
    private static var invalid: JerdError { .invalid("The MySQL publisher signature is invalid or uses an unsupported signing key.") }

    static func verify(archive: URL, armoredSignature: Data) throws {
        guard armoredSignature.count <= 16_384,
              let text = String(data: armoredSignature, encoding: .utf8),
              text.hasPrefix("-----BEGIN PGP SIGNATURE-----"), text.contains("-----END PGP SIGNATURE-----") else { throw invalid }
        let lines = text.components(separatedBy: .newlines)
        let encoded = lines.filter { !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasPrefix("=") && !$0.contains(":") }.joined()
        guard let binary = Data(base64Encoded: encoded) else { throw invalid }
        var packet = Cursor(Array(binary))
        let header = try packet.byte()
        guard header & 0x80 != 0 else { throw invalid }
        let tag: UInt8, length: Int
        if header & 0x40 != 0 {
            tag = header & 0x3f
            length = try packet.length()
        } else {
            tag = (header >> 2) & 0x0f
            switch header & 3 {
            case 0: length = Int(try packet.byte())
            case 1: length = try packet.number(2)
            case 2: length = try packet.number(4)
            default: throw invalid
            }
        }
        guard tag == 2 else { throw invalid }
        let body = try packet.take(length)
        guard packet.isAtEnd else { throw invalid }
        var signature = Cursor(body)
        guard try signature.take(4) == [4, 0, 1, 8] else { throw invalid }
        let hashedLength = try signature.number(2)
        let hashed = try signature.take(hashedLength)
        try validateSubpackets(hashed, requireFingerprint: true)
        let signedHeader = Array(body.prefix(6 + hashedLength))
        let unhashedLength = try signature.number(2)
        try validateSubpackets(signature.take(unhashedLength), requireFingerprint: false)
        let prefix = try signature.take(2)
        let bits = try signature.number(2)
        guard bits > 0, bits <= 4096 else { throw invalid }
        let rsa = try signature.take((bits + 7) / 8)
        guard signature.isAtEnd else { throw invalid }
        let lengthBytes = (0..<4).reversed().map { UInt8(truncatingIfNeeded: signedHeader.count >> ($0 * 8)) }
        let digest = try RuntimeDownload.sha256(archive, suffix: Data(signedHeader + [4, 0xff] + lengthBytes))
        guard Array(digest.prefix(2)) == prefix,
              let keyData = Data(base64Encoded: publicKey),
              let key = SecKeyCreateWithData(keyData as CFData,
                [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil),
              SecKeyVerifySignature(key, .rsaSignatureDigestPKCS1v15SHA256, digest as CFData,
                Data(Array(repeating: UInt8(0), count: 512 - rsa.count) + rsa) as CFData, nil) else { throw invalid }
    }

    private static func validateSubpackets(_ bytes: [UInt8], requireFingerprint: Bool) throws {
        var cursor = Cursor(bytes), foundFingerprint = false
        while !cursor.isAtEnd {
            let length = try cursor.length()
            guard length > 0 else { throw invalid }
            let rawType = try cursor.byte(), value = try cursor.take(length - 1)
            let type = rawType & 0x7f
            if type == 33 {
                guard value.count == 21, value[0] == 4,
                      value.dropFirst().map({ String(format: "%02X", $0) }).joined() == fingerprint else { throw invalid }
                foundFingerprint = true
            } else if rawType & 0x80 != 0, type != 2 { throw invalid }
            if type == 2, value.count != 4 { throw invalid }
        }
        if requireFingerprint, !foundFingerprint { throw invalid }
    }

    private struct Cursor {
        let bytes: [UInt8]
        var index = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }
        var isAtEnd: Bool { index == bytes.count }
        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, count <= bytes.count - index else { throw MySQLSignature.invalid }
            defer { index += count }
            return Array(bytes[index..<(index + count)])
        }
        mutating func byte() throws -> UInt8 { try take(1)[0] }
        mutating func number(_ count: Int) throws -> Int { try take(count).reduce(0) { ($0 << 8) | Int($1) } }
        mutating func length() throws -> Int {
            let first = Int(try byte())
            if first < 192 { return first }
            if first < 224 { return ((first - 192) << 8) + Int(try byte()) + 192 }
            if first == 255 { return try number(4) }
            throw MySQLSignature.invalid
        }
    }
}
