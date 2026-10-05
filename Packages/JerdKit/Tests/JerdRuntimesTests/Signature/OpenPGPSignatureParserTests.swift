import Foundation
import JerdFoundation
import JerdRuntimes
import Testing

@Suite struct OpenPGPSignatureParserTests {
    private let failure = JerdError.invalid("rejected")
    private typealias Builder = SignaturePacketBuilder

    private func parse(_ armored: Data, fingerprint: String = Builder.testFingerprint) throws -> OpenPGPSignature {
        try OpenPGPSignatureParser.parse(armored: armored, expectedFingerprint: fingerprint, rejecting: failure)
    }

    private func expectRejected(_ armored: Data) {
        #expect(throws: failure) { try parse(armored) }
    }

    @Test func oracleSignatureParsesWithItsPinnedIssuer() throws {
        let key = PinnedRSAKey.mysqlRelease2025
        let signature = try parse(OracleSignatureFixture.armored, fingerprint: key.fingerprint)
        #expect(signature.issuerFingerprint == "BCA43417C3B485DD128EC6D4B7B3B788A8D3785C")
        #expect(signature.signedHeader.count == OracleSignatureFixture.signedHeaderLength)
        #expect(signature.hashPrefix == [0x6F, 0x8A])
        #expect(signature.signatureMPI.count == 512)
    }

    @Test func wellFormedPacketKeepsSignedHeaderPrefixAndValue() throws {
        var builder = Builder()
        builder.hashPrefix = [0x12, 0x34]
        let signature = try parse(builder.armored)
        #expect(signature.signedHeader == builder.signedHeader)
        #expect(signature.hashPrefix == [0x12, 0x34])
        #expect(signature.signatureMPI == builder.value)
        #expect(signature.issuerFingerprint == Builder.testFingerprint)
    }

    @Test func armorLargerThanSixteenKilobytesIsRejected() {
        var text = String(decoding: Builder().armored, as: UTF8.self)
        text += String(repeating: " ", count: 16_385 - text.utf8.count)
        expectRejected(Data(text.utf8))
    }

    @Test func armorThatIsNotUTF8IsRejected() {
        expectRejected(Data("-----BEGIN PGP SIGNATURE-----\n".utf8) + Data([0xFF, 0xFE]))
    }

    @Test func armorWithoutBeginOrEndLineIsRejected() {
        let text = String(decoding: Builder().armored, as: UTF8.self)
        expectRejected(Data(text.replacingOccurrences(of: "-----BEGIN PGP SIGNATURE-----", with: "").utf8))
        expectRejected(Data(text.replacingOccurrences(of: "-----END PGP SIGNATURE-----", with: "").utf8))
    }

    @Test func invalidBase64IsRejected() {
        expectRejected(Data("-----BEGIN PGP SIGNATURE-----\n\n!!!!\n-----END PGP SIGNATURE-----\n".utf8))
        expectRejected(Data("-----BEGIN PGP SIGNATURE-----\nAAAA\n-----END PGP SIGNATURE-----".utf8))
    }

    @Test func firstOctetWithoutPacketBitIsRejected() {
        var packet = Builder().packet
        packet[0] &= 0x7F
        expectRejected(Builder.armor(packet))
    }

    @Test func packetThatIsNotASignatureIsRejected() {
        expectRejected(Builder.armor(Builder.newFormat(Builder().body, tag: 6)))
    }

    @Test(arguments: [UInt8(0), 1, 2])
    func oldFormatDefiniteLengthsAreAccepted(_ lengthType: UInt8) throws {
        var builder = Builder()
        builder.bits = 1_024
        builder.value = [UInt8](repeating: 0x01, count: 128)
        #expect(
            try parse(Builder.armor(Builder.oldFormat(builder.body, lengthType: lengthType))).signatureMPI.count == 128)
    }

    @Test func oldFormatIndeterminateLengthIsRejected() {
        expectRejected(Builder.armor(Builder.oldFormat(Builder().body, lengthType: 3)))
    }

    @Test func newFormatPartialLengthIsRejected() {
        expectRejected(Builder.armor([0xC2, 0xE0] + Builder().body))
    }

    @Test func newFormatTwoOctetLengthIsAccepted() throws {
        let body = Builder().body
        let length = body.count - 192
        let packet = [0xC2, UInt8(length >> 8 + 192), UInt8(length & 0xFF)] + body
        #expect(try parse(Builder.armor(packet)).issuerFingerprint == Builder.testFingerprint)
    }

    @Test func dataAfterThePacketIsRejected() {
        expectRejected(Builder.armor(Builder().packet + [0x00]))
    }

    @Test(arguments: [[UInt8]([3, 0, 1, 8]), [4, 1, 1, 8], [4, 0, 17, 8], [4, 0, 1, 2], [4, 0, 1, 10]])
    func otherVersionTypeOrAlgorithmIsRejected(_ prefix: [UInt8]) {
        var builder = Builder()
        builder.prefix = prefix
        expectRejected(builder.armored)
    }
}
