import Foundation
import JerdFoundation
import JerdRuntimes
import Testing

@Suite struct OpenPGPSubpacketTests {
    private let failure = JerdError.invalid("rejected")
    private typealias Builder = SignaturePacketBuilder

    private func parse(_ builder: Builder) throws -> OpenPGPSignature {
        try OpenPGPSignatureParser.parse(
            armored: builder.armored, expectedFingerprint: Builder.testFingerprint, rejecting: failure)
    }

    private func builder(hashed: [UInt8], unhashed: [UInt8] = []) -> Builder {
        var builder = Builder()
        builder.hashed = hashed
        builder.unhashed = unhashed
        return builder
    }

    @Test func unknownCriticalSubpacketIsRejected() {
        let notation = Builder.subpacket(type: 0x80 | 20, value: [1, 2, 3])
        #expect(throws: failure) { try parse(builder(hashed: notation + Builder.fingerprint())) }
        #expect(throws: failure) {
            try parse(builder(hashed: Builder.fingerprint(), unhashed: notation))
        }
    }

    @Test func unknownSubpacketWithoutCriticalBitIsIgnored() throws {
        let notation = Builder.subpacket(type: 20, value: [1, 2, 3])
        #expect(try parse(builder(hashed: notation + Builder.fingerprint(), unhashed: notation)).hashPrefix.count == 2)
    }

    @Test func criticalCreationTimeIsAccepted() throws {
        _ = try parse(builder(hashed: Builder.creationTime(critical: true) + Builder.fingerprint()))
    }

    @Test(arguments: [0, 3, 5])
    func creationTimeWithoutFourOctetsIsRejected(_ octets: Int) {
        #expect(throws: failure) {
            try parse(builder(hashed: Builder.creationTime(octets: octets) + Builder.fingerprint()))
        }
    }

    @Test func otherIssuerFingerprintIsRejected() {
        let other = Builder.fingerprint("BCA43417C3B485DD128EC6D4B7B3B788A8D3785C")
        #expect(throws: failure) { try parse(builder(hashed: other)) }
        #expect(throws: failure) { try parse(builder(hashed: Builder.fingerprint(), unhashed: other)) }
    }

    @Test func fingerprintOfAnotherKeyVersionOrSizeIsRejected() {
        let version5 = Builder.subpacket(type: 33, value: [0x05] + Builder.bytes(hex: Builder.testFingerprint))
        let short = Builder.subpacket(type: 33, value: [0x04] + Builder.bytes(hex: "0123"))
        #expect(throws: failure) { try parse(builder(hashed: version5)) }
        #expect(throws: failure) { try parse(builder(hashed: short)) }
    }

    @Test func fingerprintOnlyInUnhashedAreaIsRejected() {
        #expect(throws: failure) {
            try parse(builder(hashed: Builder.creationTime(), unhashed: Builder.fingerprint()))
        }
    }

    @Test func zeroLengthSubpacketIsRejected() {
        #expect(throws: failure) { try parse(builder(hashed: Builder.fingerprint() + [0x00])) }
    }

    @Test func subpacketLongerThanItsAreaIsRejected() {
        #expect(throws: failure) { try parse(builder(hashed: Builder.fingerprint() + [0x09, 20, 1])) }
    }

    /// RFC 4880 §5.2.3.1: a first octet from 192 to 254 starts a two-octet length.
    @Test func twoOctetSubpacketLengthAboveTwoHundredTwentyThreeIsAccepted() throws {
        let length = 8_384
        let first = UInt8((length - 192) >> 8 + 192)
        #expect(first == 224)
        let notation = [first, UInt8((length - 192) & 0xFF), 20] + [UInt8](repeating: 0x41, count: length - 1)
        let signature = try parse(builder(hashed: notation + Builder.fingerprint()))
        #expect(signature.signedHeader.count == 6 + notation.count + Builder.fingerprint().count)
    }

    @Test func fiveOctetSubpacketLengthIsAccepted() throws {
        let notation = [0xFF] + Builder.fourOctets(4) + [20, 1, 2, 3]
        _ = try parse(builder(hashed: notation + Builder.fingerprint()))
    }

    @Test(arguments: [0, 4_097])
    func signatureSizeOutsideOneToFourThousandNinetySixBitsIsRejected(_ bits: Int) {
        var builder = Builder()
        builder.bits = bits
        builder.value = [UInt8](repeating: 0x01, count: (bits + 7) / 8)
        #expect(throws: failure) { try parse(builder) }
    }

    @Test func fourThousandNinetySixBitSignatureIsAccepted() throws {
        var builder = Builder()
        builder.bits = 4_096
        builder.value = [UInt8](repeating: 0x80, count: 512)
        #expect(try parse(builder).signatureMPI.count == 512)
    }

    @Test func bodyThatDoesNotEndAfterTheSignatureIsRejected() {
        var longer = Builder()
        longer.trailing = [0x00]
        var shorter = Builder()
        shorter.value.removeLast()
        #expect(throws: failure) { try parse(longer) }
        #expect(throws: failure) { try parse(shorter) }
    }
}
