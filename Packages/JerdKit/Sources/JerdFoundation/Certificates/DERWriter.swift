import Foundation

/// Encodes the few ASN.1 DER values that a local CA certificate needs. Jerd makes its own CA, so
/// that the CA carries name constraints, which Caddy cannot add.
public enum DERWriter {
    /// One encoded value: a tag, the definite length, and the content.
    public static func element(tag: UInt8, _ content: Data) -> Data {
        Data([tag]) + length(content.count) + content
    }

    public static func sequence(_ parts: [Data]) -> Data { element(tag: 0x30, parts.reduce(Data(), +)) }
    public static func set(_ parts: [Data]) -> Data { element(tag: 0x31, parts.reduce(Data(), +)) }
    public static func boolean(_ value: Bool) -> Data { element(tag: 0x01, Data([value ? 0xFF : 0x00])) }
    public static func octetString(_ content: Data) -> Data { element(tag: 0x04, content) }
    public static func utf8String(_ text: String) -> Data { element(tag: 0x0C, Data(text.utf8)) }

    /// A non-negative integer from big-endian bytes, with the leading zero that DER requires when
    /// the high bit is set, and without extra leading zeros.
    public static func unsignedInteger(_ bytes: Data) -> Data {
        var content = Data(bytes.drop { $0 == 0 })
        if content.isEmpty || content[content.startIndex] & 0x80 != 0 { content.insert(0, at: 0) }
        return element(tag: 0x02, content)
    }

    /// A bit string whose last byte has `unusedBits` padding bits.
    public static func bitString(_ content: Data, unusedBits: UInt8 = 0) -> Data {
        element(tag: 0x03, Data([unusedBits]) + content)
    }

    /// An object identifier from its arcs, for example `[2, 5, 29, 30]`.
    public static func objectIdentifier(_ arcs: [UInt64]) -> Data {
        guard arcs.count >= 2 else { return element(tag: 0x06, Data()) }
        var content = base128(arcs[0] * 40 + arcs[1])
        for arc in arcs.dropFirst(2) { content += base128(arc) }
        return element(tag: 0x06, content)
    }

    /// `UTCTime` before 2050 and `GeneralizedTime` from 2050, as RFC 5280 requires.
    public static func time(_ date: Date) -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let year = calendar.component(.year, from: date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = year < 2050 ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
        return element(tag: year < 2050 ? 0x17 : 0x18, Data(formatter.string(from: date).utf8))
    }

    /// A context-specific tag `[number]`, constructed for explicit tags and nested values.
    public static func contextSpecific(_ number: UInt8, constructed: Bool, _ content: Data) -> Data {
        element(tag: 0x80 | (constructed ? 0x20 : 0) | number, content)
    }

    static func length(_ count: Int) -> Data {
        guard count >= 0x80 else { return Data([UInt8(count)]) }
        var bytes: [UInt8] = []
        var rest = count
        while rest > 0 {
            bytes.insert(UInt8(rest & 0xFF), at: 0)
            rest >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }

    private static func base128(_ value: UInt64) -> Data {
        var bytes: [UInt8] = [UInt8(value & 0x7F)]
        var rest = value >> 7
        while rest > 0 {
            bytes.insert(UInt8(rest & 0x7F) | 0x80, at: 0)
            rest >>= 7
        }
        return Data(bytes)
    }
}
