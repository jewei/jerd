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
        guard try await client.recordCount(zoneID: zone.id, hostname: hostname) == 0 else {
            throw JerdError.invalid(CloudflareMessage.recordExists(hostname))
        }
        let tunnelID = try await client.createTunnel(accountID: zone.accountID, name: tunnelName)
        do {
            let token = try TunnelToken(try await client.tunnelToken(accountID: zone.accountID, tunnelID: tunnelID))
            guard token.tunnelID == tunnelID else { throw JerdError.unavailable(CloudflareMessage.invalidResponse) }
            let recordID = try await client.createRoute(zoneID: zone.id, hostname: hostname, tunnelID: tunnelID)
            let record = CloudflareTunnelRecord(
                accountID: zone.accountID, tunnelID: tunnelID, zoneID: zone.id, dnsRecordID: recordID)
            return CloudflareProvision(token: token, record: record)
        } catch {
            try await deleteNewTunnel(tunnelID, accountID: zone.accountID, name: tunnelName, after: error)
        }
    }

    /// The record first, so the hostname never points to a deleted tunnel.
    public func deprovision(_ record: CloudflareTunnelRecord) async throws {
        try record.validate()
        let client = try client()
        try await client.deleteRecord(zoneID: record.zoneID, recordID: record.dnsRecordID)
        try await client.cleanUpConnections(accountID: record.accountID, tunnelID: record.tunnelID)
        try await client.deleteTunnel(accountID: record.accountID, tunnelID: record.tunnelID)
    }

    /// Rethrows `failure`. When the tunnel cannot be deleted, the message names it.
    private func deleteNewTunnel(
        _ tunnelID: UUID, accountID: String, name: String, after failure: any Error
    )
        async throws -> Never
    {
        do {
            try await client().deleteTunnel(accountID: accountID, tunnelID: tunnelID)
        } catch {
            throw JerdError.partialChange(
                CloudflareMessage.rollbackFailed(
                    FailureDetail.describe(failure), tunnelName: name, detail: FailureDetail.describe(error)))
        }
        throw failure
    }
}
