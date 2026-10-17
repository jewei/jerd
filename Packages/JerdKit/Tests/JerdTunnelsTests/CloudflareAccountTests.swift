import Foundation
import JerdFoundation
import Testing

@testable import JerdTunnels

@Suite("Cloudflare account")
struct CloudflareAccountTests {
    private let keychain = FakeKeychain()
    private let transport = FakeCloudflareTransport()
    private var account: CloudflareAccount { CloudflareAccount(keychain: keychain, transport: transport) }
    private let zone = FakeCloudflareTransport.exampleZone
    private let zonesJSON = FakeCloudflareTransport.success(
        #"[{"id":"\#(FakeCloudflareTransport.zone)","name":"example.com","account":{"id":"\#(FakeCloudflareTransport.account)"}}]"#
    )

    private func savedToken() -> String? {
        keychain.state.withLock { $0.items[CloudflareAccount.tokenItem] }.map { String(decoding: $0, as: UTF8.self) }
    }

    private func connected() async throws -> CloudflareAccount {
        transport.answer("GET /client/v4/zones", zonesJSON)
        let account = account
        _ = try await account.connect(apiToken: "api-token")
        return account
    }

    @Test("Connect saves the API token only after Cloudflare lists a zone")
    func connectSavesAfterCheck() async throws {
        let account = try await connected()
        #expect(savedToken() == "api-token")
        #expect(try await account.isConnected())
    }

    @Test("A token that can edit no zone is not saved")
    func noZonesIsRefused() async {
        transport.answer("GET /client/v4/zones", FakeCloudflareTransport.success("[]"))
        await #expect(throws: JerdError.invalid(CloudflareMessage.noZones)) {
            _ = try await account.connect(apiToken: "api-token")
        }
        #expect(savedToken() == nil)
    }

    @Test("A token with spaces is refused before any request")
    func malformedToken() async {
        await #expect(throws: JerdError.invalid(CloudflareMessage.tokenFormat)) {
            _ = try await account.connect(apiToken: "two words")
        }
        #expect(transport.sent.isEmpty)
    }

    @Test("Disconnect removes only the API token")
    func disconnect() async throws {
        let account = try await connected()
        try await account.disconnect()
        #expect(savedToken() == nil)
        #expect(try await !account.isConnected())
    }

    @Test("Without a saved token, Create asks the user to connect")
    func provisionNeedsToken() async {
        await #expect(throws: JerdError.unavailable(CloudflareMessage.notConnected)) {
            _ = try await account.provision(hostname: "a.example.com", zone: zone, tunnelName: "jerd-a.example.com")
        }
    }

    @Test("Provision checks the name, creates the tunnel, reads its token, then adds the CNAME")
    func provisionOrder() async throws {
        let account = try await connected()
        transport.answerCreate()
        let result = try await account.provision(
            hostname: "a.example.com", zone: zone, tunnelName: "jerd-a.example.com")
        #expect(result.record == FakeCloudflare.record)
        #expect(result.token.value == TokenSamples.valid)
        #expect(
            transport.keys.dropFirst() == [
                "GET /client/v4/zones/\(FakeCloudflareTransport.zone)/dns_records",
                "POST /client/v4/accounts/\(FakeCloudflareTransport.account)/cfd_tunnel",
                "GET \(FakeCloudflareTransport.tunnelPath)/token",
                "POST /client/v4/zones/\(FakeCloudflareTransport.zone)/dns_records",
            ])
    }

    @Test("An existing DNS record stops Create before a tunnel exists")
    func existingRecordIsNeverReplaced() async throws {
        let account = try await connected()
        transport.answerCreate()
        transport.answer(
            "GET /client/v4/zones/\(FakeCloudflareTransport.zone)/dns_records",
            FakeCloudflareTransport.success(#"[{"id":"\#(FakeCloudflareTransport.record)"}]"#))
        await #expect(throws: JerdError.invalid(CloudflareMessage.recordExists("a.example.com"))) {
            _ = try await account.provision(hostname: "a.example.com", zone: zone, tunnelName: "jerd-a.example.com")
        }
        #expect(!transport.keys.contains { $0.hasPrefix("POST") })
    }

    @Test("A failed CNAME deletes the new tunnel and reports the first failure")
    func failedRouteDeletesTunnel() async throws {
        let account = try await connected()
        transport.answerCreate()
        transport.answer(
            "POST /client/v4/zones/\(FakeCloudflareTransport.zone)/dns_records", status: 400,
            FakeCloudflareTransport.failure(code: 81053, message: "Record exists"))
        await #expect(throws: JerdError.unavailable(CloudflareMessage.failed("Record exists (81053)"))) {
            _ = try await account.provision(hostname: "a.example.com", zone: zone, tunnelName: "jerd-a.example.com")
        }
        #expect(transport.keys.last == "DELETE \(FakeCloudflareTransport.tunnelPath)")
    }

    @Test("A token for another tunnel deletes the new tunnel")
    func mismatchedTokenDeletesTunnel() async throws {
        let account = try await connected()
        transport.answerCreate(token: TokenSamples.other)
        await #expect(throws: JerdError.unavailable(CloudflareMessage.invalidResponse)) {
            _ = try await account.provision(hostname: "a.example.com", zone: zone, tunnelName: "jerd-a.example.com")
        }
        #expect(transport.keys.last == "DELETE \(FakeCloudflareTransport.tunnelPath)")
        #expect(!transport.keys.contains("POST /client/v4/zones/\(FakeCloudflareTransport.zone)/dns_records"))
    }

    @Test("When the undo also fails, the message names the tunnel to delete by hand")
    func failedUndoIsReported() async throws {
        let account = try await connected()
        transport.answerCreate()
        transport.answer("POST /client/v4/zones/\(FakeCloudflareTransport.zone)/dns_records", status: 500, "{}")
        transport.answer("DELETE \(FakeCloudflareTransport.tunnelPath)", status: 500, "{}")
        let error = try await #require(throws: JerdError.self) {
            _ = try await account.provision(hostname: "a.example.com", zone: zone, tunnelName: "jerd-a.example.com")
        }
        #expect(error.kind == .partialChange)
        #expect(error.message.contains("jerd-a.example.com"))
    }

    @Test("Deprovision deletes the record first, then the connections, then the tunnel")
    func deprovisionOrder() async throws {
        let account = try await connected()
        transport.answerRemove()
        try await account.deprovision(FakeCloudflare.record)
        let recordPath =
            "/client/v4/zones/\(FakeCloudflareTransport.zone)/dns_records/\(FakeCloudflareTransport.record)"
        #expect(
            transport.keys.dropFirst() == [
                "GET \(recordPath)", "DELETE \(recordPath)", "GET \(FakeCloudflareTransport.tunnelPath)",
                "DELETE \(FakeCloudflareTransport.tunnelPath)/connections",
                "DELETE \(FakeCloudflareTransport.tunnelPath)",
            ])
    }

    @Test("A record that the user changed since Create is never deleted")
    func changedRecordIsKept() async throws {
        let account = try await connected()
        transport.answerRemove(route: #"{"id":"\#(FakeCloudflareTransport.record)","type":"A","content":"192.0.2.1"}"#)
        try await account.deprovision(FakeCloudflare.record)
        #expect(!transport.keys.contains { $0.hasPrefix("DELETE /client/v4/zones") })
        #expect(transport.keys.last == "DELETE \(FakeCloudflareTransport.tunnelPath)")
    }

    @Test("A repeated Remove skips a tunnel that is already deleted")
    func deletedTunnelIsDone() async throws {
        let account = try await connected()
        transport.answerRemove(deletedAt: #""2026-10-16T10:00:00Z""#)
        try await account.deprovision(FakeCloudflare.record)
        #expect(transport.keys.last == "GET \(FakeCloudflareTransport.tunnelPath)")
    }

    @Test("A lost CNAME answer deletes the route that Cloudflare made, then the tunnel")
    func lostRouteAnswerIsUndone() async throws {
        let account = try await connected()
        transport.answerCreate()
        let records = "/client/v4/zones/\(FakeCloudflareTransport.zone)/dns_records"
        transport.answer("GET \(records)", FakeCloudflareTransport.success("[\(FakeCloudflareTransport.route)]"))
        transport.answerNext("GET \(records)", FakeCloudflareTransport.success("[]"))
        transport.answer("POST \(records)", status: 504, "<html>")
        transport.answer("DELETE \(records)/\(FakeCloudflareTransport.record)", FakeCloudflareTransport.success("null"))
        await #expect(throws: JerdError.unavailable(CloudflareMessage.invalidResponse)) {
            _ = try await account.provision(hostname: "a.example.com", zone: zone, tunnelName: "jerd-a.example.com")
        }
        #expect(
            transport.keys.suffix(2) == [
                "DELETE \(records)/\(FakeCloudflareTransport.record)", "DELETE \(FakeCloudflareTransport.tunnelPath)",
            ])
    }

    @Test("A Keychain failure of the API token names the Cloudflare API token, not a tunnel token")
    func keychainFailuresNameTheAPIToken() async throws {
        let account = try await connected()
        let locked = errSecInteractionNotAllowed
        keychain.state.withLock { $0.forcedStatus = locked }
        await #expect(throws: JerdError.unavailable(CloudflareMessage.keychainRead(locked))) {
            _ = try await account.isConnected()
        }
        await #expect(throws: JerdError.unavailable(CloudflareMessage.keychainRemove(locked))) {
            try await account.disconnect()
        }
        await #expect(throws: JerdError.unavailable(CloudflareMessage.keychainUpdate(locked))) {
            _ = try await account.connect(apiToken: "api-token")
        }
        keychain.state.withLock { $0.forcedStatus = errSecItemNotFound }
        await #expect(throws: JerdError.unavailable(CloudflareMessage.keychainAdd(errSecItemNotFound))) {
            _ = try await account.connect(apiToken: "api-token")
        }
        #expect(
            CloudflareMessage.keychainRemove(locked) == "Cannot remove the Cloudflare API token from Keychain (-25308)."
        )
    }
}
