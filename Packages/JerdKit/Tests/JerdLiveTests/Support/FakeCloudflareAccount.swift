import JerdTunnels

/// A Cloudflare account that records calls and never uses the network or the Keychain.
actor FakeCloudflareAccount: CloudflareProvisioning {
    private(set) var calls: [String] = []

    func isConnected() -> Bool { true }

    func connect(apiToken: String) -> [CloudflareZone] {
        calls.append("connect")
        return []
    }

    func disconnect() { calls.append("disconnect") }
    func zones() -> [CloudflareZone] { [] }

    func provision(hostname: String, zone: CloudflareZone, tunnelName: String) throws -> CloudflareProvision {
        calls.append("provision")
        throw CancellationError()
    }

    func deprovision(_ record: CloudflareTunnelRecord) { calls.append("deprovision") }
}
