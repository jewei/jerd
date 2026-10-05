import Foundation
import JerdFoundation
import Testing

@Suite struct SecretGeneratorTests {
    @Test func hexSecretsHaveTheRequestedLengthAndCase() throws {
        let lower = try SecretGenerator.system.hex(byteCount: 32)
        #expect(HexEncoding.isHex(lower, length: 64))
        let upper = try SecretGenerator.system.hex(byteCount: 24, letterCase: .upper)
        #expect(HexEncoding.isHex(upper, length: 48, letterCase: .upper))
        #expect(try SecretGenerator.system.hex(byteCount: 32) != lower)
    }

    @Test func aFailingSourceThrowsInsteadOfReturningWeakBytes() {
        let failing = SecretGenerator { _ in false }
        #expect(throws: JerdError.unavailable("Cannot create a random secret.")) { try failing.bytes(16) }
    }

    @Test func anInjectedSourceIsUsedAsGiven() throws {
        let fixed = SecretGenerator { bytes in
            for index in bytes.indices { bytes[index] = UInt8(index) }
            return true
        }
        #expect(try fixed.hex(byteCount: 3) == "000102")
    }
}
