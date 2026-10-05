import Foundation
import JerdFoundation
import JerdTunnels
import Testing

@Suite struct TunnelRegistrationTests {
    private func registration(
        name: String = "Preview", hostname: String = "preview.example.com", siteID: UUID? = nil,
        originURL: String? = nil, metricsPort: UInt16 = 20_241
    ) -> TunnelRegistration {
        TunnelRegistration(
            name: name, hostname: hostname, siteID: siteID, originURL: originURL, metricsPort: metricsPort)
    }

    @Test func aValidRegistrationPasses() throws {
        try registration().validate()
        try registration(originURL: "https://localhost:8443").validate()
        try registration(originURL: "http://[::1]:8000").validate()
        try registration(siteID: UUID()).validate()
    }

    @Test(arguments: ["", "   ", String(repeating: "n", count: 101), "Line\nbreak", "Tab\tname"])
    func aBadNameIsRefused(_ name: String) {
        #expect(throws: JerdError.invalid(TunnelMessage.invalidName)) { try registration(name: name).validate() }
    }

    @Test(arguments: [0, 80, 1_023] as [UInt16])
    func aPrivilegedMetricsPortIsRefused(_ port: UInt16) {
        #expect(throws: JerdError.invalid(TunnelMessage.invalidName)) {
            try registration(metricsPort: port).validate()
        }
    }

    @Test(arguments: [
        "https://example.com", "example.com/path", "EXAMPLE.com", "bad..example.com", "-bad.example.com",
        "bad-.example.com", "localhost", "app.localhost", "127.0.0.1", "example", "exa_mple.com",
        String(repeating: "a", count: 64) + ".com", "",
    ])
    func aMalformedHostnameIsRefused(_ hostname: String) {
        #expect(throws: JerdError.invalid(TunnelMessage.invalidHostname)) {
            try registration(hostname: hostname).validate()
        }
    }

    /// Fix of spec E 7.1.20: earlier builds accepted IPv4 literals other than 127.0.0.1.
    @Test(arguments: ["10.0.0.1", "192.168.1.20", "8.8.8.8", "example.123"])
    func anIPv4LiteralIsNotAPublicHostname(_ hostname: String) {
        #expect(throws: JerdError.invalid(TunnelMessage.invalidHostname)) {
            try registration(hostname: hostname).validate()
        }
    }

    @Test(arguments: ["1password.example.com", "123.example.com", "a-b.example.co"])
    func digitsInsideAHostnameStayAllowed(_ hostname: String) throws {
        try registration(hostname: hostname).validate()
    }

    @Test(arguments: [
        "https://public.example.com", "http://user:pass@127.0.0.1", "http://127.0.0.1/#fragment",
        "file:///tmp/file", "", "ftp://localhost", "http://127.0.0.1:0",
    ])
    func anOriginOutsideLoopbackIsRefused(_ origin: String) {
        #expect(throws: JerdError.invalid(TunnelMessage.invalidOrigin)) {
            try registration(originURL: origin).validate()
        }
    }

    @Test func aSiteAndAnOriginTogetherAreRefused() {
        #expect(throws: JerdError.invalid(TunnelMessage.invalidOrigin)) {
            try registration(siteID: UUID(), originURL: "http://127.0.0.1:8000").validate()
        }
    }

    @Test func thePublicURLUsesHTTPS() {
        #expect(registration().publicURL == URL(string: "https://preview.example.com"))
    }

    @Test func statesHaveTheirTitlesAndActivity() {
        let titles = [
            (TunnelState.stopped, "Stopped", false), (.starting, "Starting…", true), (.connecting, "Connecting…", true),
            (.connected, "Connected", true), (.reconnecting, "Reconnecting…", true), (.stopping, "Stopping…", true),
            (.failed("Reason"), "Needs attention", false),
        ]
        for (state, title, active) in titles {
            #expect(state.title == title)
            #expect(state.isActive == active)
        }
        #expect(TunnelState.failed("Reason").failureMessage == "Reason")
        #expect(TunnelState.connected.failureMessage == nil)
    }
}
