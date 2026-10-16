import Foundation
import JerdFoundation
import JerdTunnels

/// A Cloudflare account in memory for supervisor tests. It records calls and can fail each step.
actor FakeCloudflare: CloudflareProvisioning {
    var connected = true
    var provisionFailure: JerdError?
    var deprovisionFailure: JerdError?
    private(set) var calls: [String] = []

    static let record = CloudflareTunnelRecord(
        accountID: FakeCloudflareTransport.account, tunnelID: FakeCloudflareTransport.tunnel,
        zoneID: FakeCloudflareTransport.zone, dnsRecordID: FakeCloudflareTransport.record)

    func setDeprovisionFailure(_ failure: JerdError?) { deprovisionFailure = failure }

    func isConnected() -> Bool { connected }

    func connect(apiToken: String) -> [CloudflareZone] {
        calls.append("connect")
        connected = true
        return [FakeCloudflareTransport.exampleZone]
    }

    func disconnect() {
        calls.append("disconnect")
        connected = false
    }

    func zones() -> [CloudflareZone] { [FakeCloudflareTransport.exampleZone] }

    func provision(hostname: String, zone: CloudflareZone, tunnelName: String) throws -> CloudflareProvision {
        calls.append("provision \(hostname) \(tunnelName)")
        if let provisionFailure { throw provisionFailure }
        return CloudflareProvision(token: try TunnelToken(TokenSamples.valid), record: Self.record)
    }

    func deprovision(_ record: CloudflareTunnelRecord) throws {
        calls.append("deprovision \(record.dnsRecordID.prefix(4))")
        if let deprovisionFailure { throw deprovisionFailure }
    }
}
