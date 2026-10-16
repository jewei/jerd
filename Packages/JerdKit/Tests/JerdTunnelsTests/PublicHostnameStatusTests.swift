import Darwin
import Testing

@testable import JerdTunnels

@Suite("Public hostname status")
struct PublicHostnameStatusTests {
    @Test("A lookup with addresses resolves")
    func addressesResolve() {
        #expect(PublicHostnameStatus.classify(status: 0, addressCount: 2) == .resolves)
    }

    @Test("No such name, no data, and an empty answer mean the DNS record is missing")
    func missingRecord() {
        #expect(PublicHostnameStatus.classify(status: EAI_NONAME, addressCount: 0) == .missing)
        #expect(PublicHostnameStatus.classify(status: EAI_NODATA, addressCount: 0) == .missing)
        #expect(PublicHostnameStatus.classify(status: 0, addressCount: 0) == .missing)
    }

    @Test("A network or resolver failure is unknown, so the app shows no warning")
    func otherFailuresAreUnknown() {
        #expect(PublicHostnameStatus.classify(status: EAI_AGAIN, addressCount: 0) == .unknown)
        #expect(PublicHostnameStatus.classify(status: EAI_FAIL, addressCount: 0) == .unknown)
    }

    @Test("The missing-record message names the hostname and the CNAME target")
    func missingMessage() {
        let message = TunnelMessage.hostnameMissing("dev.example.com")
        #expect(message.hasPrefix("dev.example.com has no DNS record"))
        #expect(message.contains(".cfargotunnel.com"))
    }
}
