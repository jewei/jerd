import JerdFoundation

/// The rules for one signature subpacket area (RFC 4880 §5.2.3.1).
enum OpenPGPSubpackets {
    static let creationTime: UInt8 = 2
    static let issuerFingerprint: UInt8 = 33
    private static let criticalBit: UInt8 = 0x80

    /// Validates an area and returns the issuer fingerprint it contains, if any.
    ///
    /// A fingerprint subpacket anywhere must name `expectedFingerprint`. An unknown critical
    /// subpacket is refused. The creation time must have 4 octets; it may be marked critical.
    static func issuer(in area: [UInt8], expectedFingerprint: String, failure: JerdError) throws -> String? {
        var cursor = OpenPGPCursor(area, failure: failure)
        var found: String?
        while !cursor.isAtEnd {
            let length = try cursor.subpacketLength()
            guard length > 0 else { throw failure }
            let rawType = try cursor.byte()
            let value = try cursor.take(length - 1)
            switch rawType & ~criticalBit {
            case issuerFingerprint:
                found = try fingerprint(value, expected: expectedFingerprint, failure: failure)
            case creationTime:
                guard value.count == 4 else { throw failure }
            default:
                guard rawType & criticalBit == 0 else { throw failure }
            }
        }
        return found
    }

    /// A v4 fingerprint value is the version octet 4 followed by 20 octets.
    private static func fingerprint(_ value: [UInt8], expected: String, failure: JerdError) throws -> String {
        guard value.count == 21, value[0] == 4 else { throw failure }
        let text = HexEncoding.string(value.dropFirst(), letterCase: .upper)
        guard text == expected else { throw failure }
        return text
    }
}
