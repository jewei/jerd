import JerdFoundation

/// Reads OpenPGP octets in order. Every read past the end throws the caller's single failure error.
struct OpenPGPCursor {
    private let bytes: [UInt8]
    private let failure: JerdError
    private var index = 0

    init(_ bytes: [UInt8], failure: JerdError) {
        self.bytes = bytes
        self.failure = failure
    }

    var isAtEnd: Bool { index == bytes.count }

    mutating func take(_ count: Int) throws -> [UInt8] {
        guard count >= 0, count <= bytes.count - index else { throw failure }
        defer { index += count }
        return Array(bytes[index..<(index + count)])
    }

    mutating func byte() throws -> UInt8 { try take(1)[0] }

    /// A big-endian unsigned number of `count` octets (at most 4).
    mutating func number(_ count: Int) throws -> Int {
        try take(count).reduce(0) { ($0 << 8) | Int($1) }
    }

    /// A new-format packet length (RFC 4880 §4.2.2). Partial lengths (224–254) are refused.
    mutating func packetLength() throws -> Int {
        let first = Int(try byte())
        switch first {
        case 0..<192: return first
        case 192..<224: return ((first - 192) << 8) + Int(try byte()) + 192
        case 255: return try number(4)
        default: throw failure
        }
    }

    /// A subpacket length (RFC 4880 §5.2.3.1): two octets for every first octet from 192 to 254.
    mutating func subpacketLength() throws -> Int {
        let first = Int(try byte())
        switch first {
        case 0..<192: return first
        case 192..<255: return ((first - 192) << 8) + Int(try byte()) + 192
        default: return try number(4)
        }
    }
}
