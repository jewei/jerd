import Foundation
import JerdFoundation
import Testing

@Suite struct HexEncodingTests {
    @Test func bytesBecomeTwoDigitsEach() {
        #expect(HexEncoding.string([0x00, 0xAB, 0xFF]) == "00abff")
        #expect(HexEncoding.string([0xAB], letterCase: .upper) == "AB")
    }

    @Test func checksRequireTheExactLengthAndCase() {
        #expect(HexEncoding.isHex("00ff", length: 4))
        #expect(!HexEncoding.isHex("00FF", length: 4))
        #expect(!HexEncoding.isHex("00ff0", length: 4))
        #expect(!HexEncoding.isHex("00fg", length: 4))
    }
}
