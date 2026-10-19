import Foundation
import Testing

@testable import JerdFoundation

@Suite struct DERWriterTests {
    @Test(arguments: [(0, [0x00]), (0x7F, [0x7F]), (0x80, [0x81, 0x80]), (0x100, [0x82, 0x01, 0x00])])
    func lengthsUseTheShortestForm(count: Int, bytes: [UInt8]) {
        #expect(DERWriter.length(count) == Data(bytes))
    }

    @Test func knownObjectIdentifiersEncodeAsInRFC5480() {
        #expect(
            DERWriter.objectIdentifier(CertificateObjectIdentifier.ecPublicKey)
                == Data([0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]))
        #expect(
            DERWriter.objectIdentifier(CertificateObjectIdentifier.nameConstraints)
                == Data([0x06, 0x03, 0x55, 0x1D, 0x1E]))
    }

    @Test func integersAreMinimalAndPositive() {
        #expect(DERWriter.unsignedInteger(Data([0x00, 0x00, 0x05])) == Data([0x02, 0x01, 0x05]))
        #expect(DERWriter.unsignedInteger(Data([0x80])) == Data([0x02, 0x02, 0x00, 0x80]))
        #expect(DERWriter.unsignedInteger(Data()) == Data([0x02, 0x01, 0x00]))
    }

    @Test func timesSwitchToGeneralizedTimeIn2050() {
        let before = Date(timeIntervalSince1970: 2_524_607_999)  // 2049-12-31 23:59:59 UTC
        #expect(DERWriter.time(before) == Data([0x17, 0x0D]) + Data("491231235959Z".utf8))
        #expect(DERWriter.time(before.addingTimeInterval(1)) == Data([0x18, 0x0F]) + Data("20500101000000Z".utf8))
    }

    @Test func anEmptyValueIsValid() throws {
        #expect(try DERElement.single(in: Data([0x04, 0x00])) == DERElement(tag: 0x04, content: Data()))
    }

    @Test func theReaderReturnsWhatTheWriterWrote() throws {
        let long = Data(repeating: 0xAB, count: 300)
        let data = DERWriter.sequence([DERWriter.boolean(true), DERWriter.octetString(long)])
        let children = try DERElement.single(in: data).children()
        #expect(children == [DERElement(tag: 0x01, content: Data([0xFF])), DERElement(tag: 0x04, content: long)])
    }

    @Test(
        arguments: [
            [0x30, 0x03, 0x01, 0x01],  // the content is shorter than its length
            [0x30, 0x81, 0x01, 0x00],  // a long form for a short length
            [0x04, 0x80],  // an indefinite length
            [0x01, 0x01, 0xFF, 0x00],  // a byte after the value
            [0x30, 0x82, 0x00, 0x80],  // a long form with a leading zero byte
            [0x30, 0x85, 0x01, 0x00, 0x00, 0x00, 0x00],  // a length of more than 4 bytes
            [0x1F, 0x01, 0x00],  // a multi-byte tag
            [0x30, 0x82, 0x01],  // the data ends inside the length
        ] as [[UInt8]])
    func theReaderRefusesInvalidDER(bytes: [UInt8]) {
        #expect(throws: JerdError.self) { try DERElement.single(in: Data(bytes)) }
    }
}
