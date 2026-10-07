import Foundation

/// The bytes that RFC 4880 §5.2.4 appends to the document before a v4 signature digest.
package enum OpenPGPTrailer {
    /// `signedHeader`, then `0x04 0xFF`, then the header length as a 4-octet big-endian number.
    package static func bytes(for signedHeader: [UInt8]) -> Data {
        let count = UInt32(truncatingIfNeeded: signedHeader.count)
        let length = (0..<4).reversed().map { UInt8(truncatingIfNeeded: count >> (UInt32($0) * 8)) }
        return Data(signedHeader + [0x04, 0xFF] + length)
    }
}
