import Foundation

/// Builds OpenPGP v4 signature packet bodies for parser and verifier tests.
struct SignaturePacketBuilder {
    static let testFingerprint = "0123456789ABCDEF0123456789ABCDEF01234567"

    var prefix: [UInt8] = [0x04, 0x00, 0x01, 0x08]
    var hashed: [UInt8] = SignaturePacketBuilder.creationTime() + SignaturePacketBuilder.fingerprint()
    var unhashed: [UInt8] = []
    var hashPrefix: [UInt8] = [0x00, 0x00]
    var bits = 2_048
    var value = [UInt8](repeating: 0xAB, count: 256)
    var trailing: [UInt8] = []

    /// The signed part: version through the hashed subpackets.
    var signedHeader: [UInt8] { prefix + Self.twoOctets(hashed.count) + hashed }

    var body: [UInt8] {
        signedHeader + Self.twoOctets(unhashed.count) + unhashed + hashPrefix + Self.twoOctets(bits) + value
            + trailing
    }

    /// The body in a new-format signature packet (tag 2) with a five-octet length.
    var packet: [UInt8] { Self.newFormat(body) }

    var armored: Data { Self.armor(packet) }

    static func twoOctets(_ value: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: value >> 8), UInt8(value & 0xFF)] }

    static func fourOctets(_ value: Int) -> [UInt8] {
        [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }
    }

    /// One subpacket with a one-octet length.
    static func subpacket(type: UInt8, value: [UInt8]) -> [UInt8] {
        [UInt8(value.count + 1), type] + value
    }

    static func creationTime(critical: Bool = false, octets: Int = 4) -> [UInt8] {
        subpacket(type: critical ? 0x82 : 0x02, value: [UInt8](repeating: 0x5F, count: octets))
    }

    static func fingerprint(_ hex: String = testFingerprint) -> [UInt8] {
        subpacket(type: 33, value: [0x04] + bytes(hex: hex))
    }

    static func newFormat(_ body: [UInt8], tag: UInt8 = 2) -> [UInt8] {
        [0xC0 | tag, 0xFF] + fourOctets(body.count) + body
    }

    /// An old-format packet with length type 0 (one octet), 1 (two), 2 (four), or 3 (indeterminate).
    static func oldFormat(_ body: [UInt8], lengthType: UInt8) -> [UInt8] {
        let header: UInt8 = 0x80 | (2 << 2) | lengthType
        switch lengthType {
        case 0: return [header, UInt8(body.count)] + body
        case 1: return [header] + twoOctets(body.count) + body
        case 2: return [header] + fourOctets(body.count) + body
        default: return [header] + body
        }
    }

    static func armor(_ packet: [UInt8]) -> Data {
        let base64 = Data(packet).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        let text = "-----BEGIN PGP SIGNATURE-----\nComment: test\n\n\(base64)\n=AAAA\n-----END PGP SIGNATURE-----\n"
        return Data(text.utf8)
    }

    static func bytes(hex: String) -> [UInt8] {
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            result.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        return result
    }
}
