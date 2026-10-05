import Foundation
import JerdFoundation

/// Parses an armored detached OpenPGP signature that holds exactly one v4 signature packet.
///
/// Only binary-document signatures (type 0x00) with RSA (algorithm 1) and SHA-256 (algorithm 8)
/// are accepted. The hashed area must name the expected issuer fingerprint. Every failure throws
/// the single error `rejecting`, so a caller never learns which rule failed.
package enum OpenPGPSignatureParser {
    /// Signature packet tag (RFC 4880 §5.2).
    static let signatureTag: UInt8 = 2
    /// Version 4, binary document, RSA, SHA-256.
    static let acceptedPrefix: [UInt8] = [0x04, 0x00, 0x01, 0x08]
    /// The largest RSA modulus that is accepted, in bits.
    static let maximumBits = 4_096

    package static func parse(
        armored: Data, expectedFingerprint: String, rejecting failure: JerdError
    ) throws -> OpenPGPSignature {
        let packet = try OpenPGPArmor.decode(armored, failure: failure)
        let body = try packetBody(packet, failure: failure)
        return try signature(body, expectedFingerprint: expectedFingerprint, failure: failure)
    }

    /// The body of the one signature packet. Trailing data after it is refused.
    static func packetBody(_ packet: [UInt8], failure: JerdError) throws -> [UInt8] {
        var cursor = OpenPGPCursor(packet, failure: failure)
        let header = try cursor.byte()
        guard header & 0x80 != 0 else { throw failure }
        let tag: UInt8
        let length: Int
        if header & 0x40 != 0 {
            tag = header & 0x3F
            length = try cursor.packetLength()
        } else {
            tag = (header >> 2) & 0x0F
            switch header & 0x03 {
            case 0: length = try cursor.number(1)
            case 1: length = try cursor.number(2)
            case 2: length = try cursor.number(4)
            default: throw failure
            }
        }
        guard tag == signatureTag else { throw failure }
        let body = try cursor.take(length)
        guard cursor.isAtEnd else { throw failure }
        return body
    }

    static func signature(_ body: [UInt8], expectedFingerprint: String, failure: JerdError) throws -> OpenPGPSignature {
        var cursor = OpenPGPCursor(body, failure: failure)
        guard try cursor.take(4) == acceptedPrefix else { throw failure }
        let hashedLength = try cursor.number(2)
        let hashed = try cursor.take(hashedLength)
        let issuer = try OpenPGPSubpackets.issuer(
            in: hashed, expectedFingerprint: expectedFingerprint, failure: failure)
        guard let issuer else { throw failure }
        let unhashed = try cursor.take(try cursor.number(2))
        _ = try OpenPGPSubpackets.issuer(in: unhashed, expectedFingerprint: expectedFingerprint, failure: failure)
        let hashPrefix = try cursor.take(2)
        let bits = try cursor.number(2)
        guard (1...maximumBits).contains(bits) else { throw failure }
        let value = try cursor.take((bits + 7) / 8)
        guard cursor.isAtEnd else { throw failure }
        return OpenPGPSignature(
            signedHeader: Array(body.prefix(6 + hashedLength)), hashPrefix: hashPrefix, signatureMPI: value,
            issuerFingerprint: issuer)
    }
}
