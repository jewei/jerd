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

    /// Regression test: earlier builds accepted IPv4 literals other than 127.0.0.1. A new or
    /// edited registration refuses them; the stored rule of earlier builds still accepts them.
    @Test(arguments: ["10.0.0.1", "192.168.1.20", "8.8.8.8", "example.123"])
    func anIPv4LiteralIsNotAPublicHostname(_ hostname: String) throws {
        #expect(throws: JerdError.invalid(TunnelMessage.addressHostname)) {
            try registration(hostname: hostname).validate()
        }
        try registration(hostname: hostname).validateStored()
        #expect(
            TunnelSnapshot(registration: registration(hostname: hostname), state: .stopped).settingsIssue
                == TunnelMessage.addressHostname)
    }

    @Test(arguments: ["127.0.0.1", "localhost", "app.localhost", "https://example.com", ""])
    func theStoredRuleStillRefusesWhatEarlierBuildsRefused(_ hostname: String) {
        #expect(throws: JerdError.invalid(TunnelMessage.invalidHostname)) {
            try registration(hostname: hostname).validateStored()
        }
    }

    /// Cloudflare cannot route a `.test` name, and Caddy must never receive another site's
    /// `.test` name as the restored Host. The stored rule still loads such a file.
    @Test(arguments: ["shop.test", "preview.shop.test"])
    func aTestNameIsNotAPublicHostname(_ hostname: String) throws {
        #expect(throws: JerdError.invalid(TunnelMessage.localHostname)) {
            try registration(hostname: hostname).validate()
        }
        try registration(hostname: hostname).validateStored()
        #expect(
            TunnelSnapshot(registration: registration(hostname: hostname), state: .stopped).settingsIssue
                == TunnelMessage.localHostname)
    }

    /// The web environment restores only a `PublicHostname`, so Save must accept exactly those
    /// names. Otherwise a saved route could have no restored Host.
    @Test(arguments: [
        "preview.example.com", "1password.example.com", "a-b.example.co", "shop.test", "10.0.0.1",
        "app.localhost", "UPPER.example.com", "example", "bad..example.com",
        String(repeating: "a", count: 64) + ".com",
        Array(repeating: String(repeating: "a", count: 63), count: 4)
            .joined(separator: "."),
    ])
    func theSaveRuleAcceptsExactlyThePublicHostnames(_ hostname: String) {
        let saves = (try? registration(hostname: hostname).validate()) != nil
        #expect(saves == (PublicHostname(hostname) != nil))
    }

    @Test func localRoutingWithoutADestinationIsRefused() {
        var local = registration()
        local.routing = .local
        #expect(throws: JerdError.invalid(TunnelMessage.localDestinationMissing)) { try local.validate() }
        local.siteID = UUID()
        #expect(throws: Never.self) { try local.validate() }
    }

    /// cloudflared sends the request path unchanged, so a path (also `/`) or a query cannot work.
    @Test(arguments: [
        "http://127.0.0.1:8000/", "http://127.0.0.1:8000/app", "http://127.0.0.1:8000?key=value",
        "http://127.0.0.1:8000?",
    ])
    func localRoutingRefusesAnAddressWithAPathOrQuery(_ address: String) {
        var local = registration(originURL: address)
        local.routing = .local
        #expect(throws: JerdError.invalid(TunnelMessage.localAddressPath)) { try local.validate() }
    }

    /// A Cloudflare route keeps the reference rule of earlier builds: a path is only a note there.
    @Test func cloudflareRoutingKeepsTheEarlierAddressRule() throws {
        try registration(originURL: "http://127.0.0.1:8000/app").validate()
        try registration().validate()
    }

    /// Sites do not start when Jerd opens, so only a Jerd route to a Jerd site cannot connect then.
    @Test func onlyAJerdRouteToASiteCannotConnectAtLaunch() {
        var tunnel = registration(siteID: UUID())
        #expect(tunnel.canConnectOnLaunch)
        tunnel.routing = .local
        #expect(!tunnel.canConnectOnLaunch)
        tunnel.siteID = nil
        tunnel.originURL = "http://127.0.0.1:8000"
        #expect(tunnel.canConnectOnLaunch)
    }

    @Test func aValidRegistrationHasNoSettingsIssue() {
        #expect(TunnelSnapshot(registration: registration(), state: .stopped).settingsIssue == nil)
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
