import JerdFoundation
import Testing

@Suite struct PublicHostnameTests {
    @Test(arguments: [
        "preview.example.com", "a.co", "1password.example.com", "123.example.com", "a-b.example.co",
        String(repeating: "a", count: 63) + ".com",
    ])
    func aLowercaseDNSNameIsAPublicHostname(_ text: String) throws {
        let hostname = try #require(PublicHostname(text))
        #expect(hostname.value == text)
        #expect(hostname.description == text)
    }

    @Test(arguments: [
        "", "example", "UPPER.example.com", " public.example.com", "public.example.com.", "public..example.com",
        "-public.example.com", "public-.example.com", "exa_mple.com", "café.example.com", "*.example.com",
        "public.example.com:443", "https://public.example.com", "{http.request.host}",
        "public.example.com\r\nHost: other.example", String(repeating: "a", count: 64) + ".com",
        Array(repeating: String(repeating: "a", count: 63), count: 4).joined(separator: "."),
    ])
    func aNameThatBreaksTheDNSSyntaxIsRefused(_ text: String) {
        #expect(PublicHostname(text) == nil)
        #expect(!HostnamePolicy.isDNSName(text))
    }

    @Test(arguments: ["localhost", "app.localhost", "shop.test", "preview.shop.test"])
    func aLocalNameIsRefused(_ text: String) {
        #expect(PublicHostname(text) == nil)
    }

    @Test(arguments: ["127.0.0.1", "10.0.0.1", "8.8.8.8", "example.123"])
    func anIPv4LiteralIsRefused(_ text: String) {
        #expect(PublicHostname.isAddressLiteral(text))
        #expect(HostnamePolicy.isDNSName(text))
        #expect(PublicHostname(text) == nil)
    }

    @Test func theLengthLimitIsInclusive() throws {
        let exact = String(repeating: "a.", count: 125) + "com"
        #expect(exact.utf8.count == 253)
        #expect(PublicHostname(exact) != nil)
        #expect(PublicHostname("a" + exact) == nil)
    }

    @Test func hostnamesSortByText() throws {
        let names = ["b.example.com", "a.example.com"].compactMap(PublicHostname.init)
        #expect(names.sorted().map(\.value) == ["a.example.com", "b.example.com"])
    }
}
