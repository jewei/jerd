import Foundation
import JerdFoundation
import Testing

@testable import JerdTunnels

@Suite("Cloudflare API client")
struct CloudflareClientTests {
    private let transport = FakeCloudflareTransport()
    private var client: CloudflareClient { CloudflareClient(token: "api-token", transport: transport) }

    @Test("Zones come from every page, sorted, with the token only in the Authorization header")
    func zonesFromEveryPage() async throws {
        let first =
            #"[{"id":"\#(FakeCloudflareTransport.zone)","name":"zeta.dev","account":{"id":"\#(FakeCloudflareTransport.account)"}}]"#
        transport.answer(
            "GET /client/v4/zones",
            #"{"success":true,"errors":[],"result":\#(first),"result_info":{"total_pages":1}}"#)
        let zones = try await client.zones()
        #expect(
            zones == [
                CloudflareZone(
                    id: FakeCloudflareTransport.zone, name: "zeta.dev", accountID: FakeCloudflareTransport.account)
            ])
        let sent = try #require(transport.sent.first)
        #expect(sent.authorization == "Bearer api-token")
        #expect(sent.query == "page=1&per_page=50&status=active")
        #expect(!(sent.query ?? "").contains("api-token"))
    }

    @Test("A zone with an unexpected ID is skipped")
    func badZoneIDIsSkipped() async throws {
        transport.answer(
            "GET /client/v4/zones",
            FakeCloudflareTransport.success(#"[{"id":"../x","name":"a.dev","account":{"id":"x"}}]"#))
        #expect(try await client.zones().isEmpty)
    }

    @Test("HTTP 401 says that the token was rejected")
    func unauthorized() async {
        transport.answer(
            "GET /client/v4/zones", status: 401, FakeCloudflareTransport.failure(code: 9109, message: "Invalid"))
        await #expect(throws: JerdError.invalid(CloudflareMessage.tokenRejected)) { try await client.zones() }
    }

    @Test("A refusal shows Cloudflare's message and code")
    func refusalShowsMessage() async {
        transport.answer(
            "POST /client/v4/accounts/\(FakeCloudflareTransport.account)/cfd_tunnel", status: 400,
            FakeCloudflareTransport.failure(code: 1003, message: "Invalid name"))
        await #expect(throws: JerdError.unavailable(CloudflareMessage.failed("Invalid name (1003)"))) {
            _ = try await client.createTunnel(accountID: FakeCloudflareTransport.account, name: "jerd-a.example.com")
        }
    }

    @Test("A token without a needed permission gets the list of permissions to add")
    func missingPermissionListsPermissions() async {
        transport.answer(
            "POST /client/v4/accounts/\(FakeCloudflareTransport.account)/cfd_tunnel", status: 403,
            FakeCloudflareTransport.failure(code: 10000, message: "Authentication error"))
        let expected = CloudflareMessage.missingPermission("Authentication error (10000)")
        #expect(expected.contains(CloudflareMessage.tokenPermissions))
        await #expect(throws: JerdError.invalid(expected)) {
            _ = try await client.createTunnel(accountID: FakeCloudflareTransport.account, name: "jerd-a.example.com")
        }
    }

    @Test("Code 10000 means a missing permission even without HTTP 403")
    func authenticationCodeListsPermissions() async {
        transport.answer(
            "GET /client/v4/zones/\(FakeCloudflareTransport.zone)/dns_records", status: 400,
            FakeCloudflareTransport.failure(code: 10000, message: "Authentication error"))
        await #expect(
            throws: JerdError.invalid(CloudflareMessage.missingPermission("Authentication error (10000)"))
        ) {
            _ = try await client.records(zoneID: FakeCloudflareTransport.zone, hostname: "a.example.com")
        }
    }

    @Test("A new tunnel is locally managed")
    func createTunnelBody() async throws {
        transport.answerCreate()
        let id = try await client.createTunnel(accountID: FakeCloudflareTransport.account, name: "jerd-a.example.com")
        #expect(id == FakeCloudflareTransport.tunnel)
        let body = try #require(transport.sent.first?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: String])
        #expect(json == ["name": "jerd-a.example.com", "config_src": "local"])
    }

    @Test("The route is a proxied CNAME to the tunnel")
    func routeBody() async throws {
        transport.answerCreate()
        let id = try await client.createRoute(
            zoneID: FakeCloudflareTransport.zone, hostname: "a.example.com", tunnelID: FakeCloudflareTransport.tunnel)
        #expect(id == FakeCloudflareTransport.record)
        let body = try #require(transport.sent.first?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        #expect(json["type"] as? String == "CNAME")
        #expect(json["name"] as? String == "a.example.com")
        #expect(
            json["content"] as? String == "\(FakeCloudflareTransport.tunnel.uuidString.lowercased()).cfargotunnel.com")
        #expect(json["proxied"] as? Bool == true)
    }

    @Test("Delete accepts a resource that is already gone")
    func deleteAcceptsMissing() async throws {
        transport.answer("DELETE \(FakeCloudflareTransport.tunnelPath)", status: 404, "{}")
        try await client.deleteTunnel(
            accountID: FakeCloudflareTransport.account, tunnelID: FakeCloudflareTransport.tunnel)
    }

    @Test("A path segment with another character is refused before any request")
    func unsafeSegmentIsRefused() async {
        await #expect(throws: JerdError.self) {
            try await client.deleteRecord(zoneID: "../../user", recordID: FakeCloudflareTransport.record)
        }
        #expect(transport.sent.isEmpty)
    }

    @Test("A body that is not the Cloudflare envelope is an invalid response")
    func invalidBody() async {
        transport.answer("GET /client/v4/zones", "<html>")
        await #expect(throws: JerdError.unavailable(CloudflareMessage.invalidResponse)) { try await client.zones() }
    }
}
