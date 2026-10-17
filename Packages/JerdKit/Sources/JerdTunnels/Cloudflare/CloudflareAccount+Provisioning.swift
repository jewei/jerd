import Foundation
import JerdFoundation

extension CloudflareAccount {
    /// Checks that the name is free first, so Jerd never replaces a record. The connector token
    /// must name the new tunnel. Any failure after the tunnel exists deletes it again.
    public func provision(
        hostname: String, zone: CloudflareZone, tunnelName: String
    ) async throws
        -> CloudflareProvision
    {
        let client = try client()
        guard try await client.records(zoneID: zone.id, hostname: hostname).isEmpty else {
            throw JerdError.invalid(CloudflareMessage.recordExists(hostname))
        }
        let tunnelID: UUID
        do {
            tunnelID = try await client.createTunnel(accountID: zone.accountID, name: tunnelName)
        } catch {
            throw await createFailure(error, client: client, zone: zone, name: tunnelName)
        }
        do {
            let token = try TunnelToken(try await client.tunnelToken(accountID: zone.accountID, tunnelID: tunnelID))
            guard token.tunnelID == tunnelID else { throw JerdError.unavailable(CloudflareMessage.invalidResponse) }
            let recordID = try await client.createRoute(zoneID: zone.id, hostname: hostname, tunnelID: tunnelID)
            let record = CloudflareTunnelRecord(
                accountID: zone.accountID, tunnelID: tunnelID, zoneID: zone.id, dnsRecordID: recordID)
            return CloudflareProvision(token: token, record: record)
        } catch {
            try await deleteNewTunnel(tunnelID, hostname: hostname, zone: zone, name: tunnelName, after: error)
        }
    }

    /// The record first, so the hostname never points to a deleted tunnel. The record is deleted
    /// only while it is still a CNAME to this tunnel: the user may have changed it since. A tunnel
    /// that is already deleted is done, so Remove can be repeated.
    public func deprovision(_ record: CloudflareTunnelRecord) async throws {
        try record.validate()
        let client = try client()
        if let current = try await client.record(zoneID: record.zoneID, recordID: record.dnsRecordID),
            current.routes(to: record.tunnelID)
        {
            try await client.deleteRecord(zoneID: record.zoneID, recordID: record.dnsRecordID)
        }
        guard try await !client.isTunnelDeleted(accountID: record.accountID, tunnelID: record.tunnelID) else { return }
        try await client.cleanUpConnections(accountID: record.accountID, tunnelID: record.tunnelID)
        try await client.deleteTunnel(accountID: record.accountID, tunnelID: record.tunnelID)
    }

    /// A Create whose answer was lost leaves a tunnel with this name, and Cloudflare then refuses
    /// each new tunnel with the same name. Jerd cannot prove that it made that tunnel, so it does
    /// not delete it; the message names it. When the lookup fails, the first failure says more.
    private func createFailure(
        _ failure: any Error, client: CloudflareClient, zone: CloudflareZone, name: String
    ) async -> any Error {
        do {
            guard try await client.hasTunnel(accountID: zone.accountID, name: name) else { return failure }
            return JerdError.partialChange(CloudflareMessage.tunnelExists(name))
        } catch {
            return failure
        }
    }

    /// Deletes a route that Cloudflare may have created although its answer was lost, then the
    /// tunnel, and rethrows `failure`. When a step fails, the message names the tunnel. The undo
    /// runs in the caller's task; nothing cancels a Create.
    private func deleteNewTunnel(
        _ tunnelID: UUID, hostname: String, zone: CloudflareZone, name: String, after failure: any Error
    ) async throws -> Never {
        do {
            let client = try client()
            for route in try await client.records(zoneID: zone.id, hostname: hostname) where route.routes(to: tunnelID)
            {
                try await client.deleteRecord(zoneID: zone.id, recordID: route.id)
            }
            try await client.deleteTunnel(accountID: zone.accountID, tunnelID: tunnelID)
        } catch {
            throw JerdError.partialChange(
                CloudflareMessage.rollbackFailed(
                    FailureDetail.describe(failure), tunnelName: name, detail: FailureDetail.describe(error)))
        }
        throw failure
    }
}
