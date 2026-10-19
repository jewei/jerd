import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct SiteAliasCodingTests {
    @Test func aSiteWithoutAliasesKeepsTheEarlierFormAndAliasesRoundTrip() throws {
        var site = Samples.site(URL(fileURLWithPath: "/p/app"), hostname: "app.test")
        let plain = try ConfigurationCodec.encode(Samples.configuration([site]))
        #expect(!String(decoding: plain, as: UTF8.self).contains("aliases"))
        site.aliases = ["api.app.test"]
        let configuration = Samples.configuration([site])
        let bytes = try ConfigurationCodec.encode(configuration)
        #expect(String(decoding: bytes, as: UTF8.self).contains("\"aliases\" : [\n        \"api.app.test\""))
        #expect(try ConfigurationCodec.decode(bytes) == configuration)
    }

    @Test func aNameUsedTwiceAcrossSitesIsCorrupt() throws {
        var one = Samples.site(URL(fileURLWithPath: "/p/one"), hostname: "one.test")
        let two = Samples.site(URL(fileURLWithPath: "/p/two"), hostname: "two.test")
        one.aliases = ["TWO.test"]
        #expect(throws: JerdError.corrupt("Configuration contains an invalid version or duplicate records.")) {
            try ConfigurationCodec.validate(Samples.configuration([one, two]))
        }
        one.aliases = ["bad alias"]
        #expect(throws: JerdError.self) { try ConfigurationCodec.validate(Samples.configuration([one, two])) }
    }
}
