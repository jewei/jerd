import Foundation
import JerdFoundation

/// The Cloudflare API calls that Jerd uses, with one API token. Every path segment is a checked
/// ID or a fixed word, and the token goes only in the Authorization header.
struct CloudflareClient: Sendable {
    let token: String
    let transport: any CloudflareTransporting

    /// The active zones that the token can read, in name order.
    func zones() async throws -> [CloudflareZone] {
        var zones: [CloudflareZone] = []
        for page in 1...20 {
            let response: CloudflareResponse<[ZoneResult]> = try await call(
                "GET", ["zones"], query: ["status": "active", "per_page": "50", "page": String(page)])
            zones += try response.requireResult().compactMap(\.zone)
            if page >= (response.resultInfo?.totalPages ?? 1) { break }
        }
        return zones.sorted { $0.name < $1.name }
    }

    /// A locally managed tunnel: its route comes from the connector's `config.yml`.
    func createTunnel(accountID: String, name: String) async throws -> UUID {
        let body = try JSONEncoder().encode(["name": name, "config_src": "local"])
        let response: CloudflareResponse<TunnelResult> = try await call(
            "POST", ["accounts", accountID, "cfd_tunnel"], body: body)
        return try response.requireResult().id
    }

    func tunnelToken(accountID: String, tunnelID: UUID) async throws -> String {
        let response: CloudflareResponse<String> = try await call(
            "GET", ["accounts", accountID, "cfd_tunnel", tunnelID.uuidString.lowercased(), "token"])
        return try response.requireResult()
    }

    /// The number of DNS records of any type with exactly this name.
    func recordCount(zoneID: String, hostname: String) async throws -> Int {
        let response: CloudflareResponse<[RecordResult]> = try await call(
            "GET", ["zones", zoneID, "dns_records"], query: ["name": hostname])
        return try response.requireResult().count
    }

    /// A proxied CNAME from the hostname to the tunnel. Returns the record ID.
    func createRoute(zoneID: String, hostname: String, tunnelID: UUID) async throws -> String {
        let body = try JSONEncoder().encode(
            RouteBody(
                name: hostname, content: "\(tunnelID.uuidString.lowercased()).cfargotunnel.com",
                comment: "Created by Jerd"))
        let response: CloudflareResponse<RecordResult> = try await call(
            "POST", ["zones", zoneID, "dns_records"], body: body)
        let id = try response.requireResult().id
        guard CloudflareTunnelRecord.isIdentifier(id) else {
            throw JerdError.unavailable(CloudflareMessage.invalidResponse)
        }
        return id
    }

    /// Deletes one DNS record. A record that is already gone is not an error.
    func deleteRecord(zoneID: String, recordID: String) async throws {
        try await delete(["zones", zoneID, "dns_records", recordID])
    }

    /// Removes the stale connections of a stopped connector, so the tunnel can be deleted.
    func cleanUpConnections(accountID: String, tunnelID: UUID) async throws {
        try await delete(["accounts", accountID, "cfd_tunnel", tunnelID.uuidString.lowercased(), "connections"])
    }

    /// Deletes a tunnel. A tunnel that is already gone is not an error.
    func deleteTunnel(accountID: String, tunnelID: UUID) async throws {
        try await delete(["accounts", accountID, "cfd_tunnel", tunnelID.uuidString.lowercased()])
    }

    private func delete(_ path: [String]) async throws {
        let (status, body) = try await send("DELETE", path, query: [:], body: nil)
        if status == 404 { return }
        _ = try CloudflareResponse<CloudflareIgnoredResult>.decode(status: status, body: body)
    }

    private func call<Result: Decodable>(
        _ method: String, _ path: [String], query: [String: String] = [:], body: Data? = nil
    ) async throws -> CloudflareResponse<Result> {
        let (status, data) = try await send(method, path, query: query, body: body)
        return try CloudflareResponse<Result>.decode(status: status, body: data)
    }

    private func send(
        _ method: String, _ path: [String], query: [String: String], body: Data?
    ) async throws -> (
        Int, Data
    ) {
        let request = try CloudflareRequest.make(method, path, query: query, body: body, token: token)
        do {
            let (status, data) = try await transport.send(request)
            return (status, data)
        } catch let error as JerdError {
            throw error
        } catch {
            throw JerdError.unavailable(CloudflareMessage.unreachable(error.localizedDescription))
        }
    }
}
