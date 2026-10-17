import Foundation
import JerdTunnels

extension TunnelsModel {
    /// Looks up the public hostname of each connected tunnel once per connection. "Connected" only
    /// means that Cloudflare accepts the connector, so a missing DNS record is otherwise silent.
    /// A tunnel that is not connected loses its warning, so the next Connect checks again.
    func checkHostnames() {
        let connected = registrations.filter { state(of: $0.id) == .connected }
        let connectedIDs = Set(connected.map(\.id))
        checkedHostnames = checkedHostnames.filter { connectedIDs.contains($0.key) }
        let warnings = hostnameWarnings.filter { connectedIDs.contains($0.key) }
        if warnings != hostnameWarnings { hostnameWarnings = warnings }
        let pending = connected.filter { checkedHostnames[$0.id] != $0.hostname }
        guard !pending.isEmpty, hostnameCheck == nil else { return }
        for tunnel in pending { checkedHostnames[tunnel.id] = tunnel.hostname }
        hostnameCheck = Task {
            for tunnel in pending { await lookUp(tunnel) }
            hostnameCheck = nil
        }
    }

    /// Looks up the public hostname again, for example after the user added the DNS record. While
    /// another lookup runs, this one waits for it, so the click is never lost.
    @discardableResult
    public func checkHostnameAgain(_ id: UUID) -> Task<Void, Never>? {
        checkedHostnames[id] = nil
        guard let running = hostnameCheck else {
            checkHostnames()
            return hostnameCheck
        }
        return Task {
            await running.value
            checkHostnames()
            await hostnameCheck?.value
        }
    }

    /// An unknown answer, for example without network, shows no warning and is retried on the
    /// next refresh. A result for a hostname that changed meanwhile is dropped.
    private func lookUp(_ tunnel: TunnelRegistration) async {
        let status = await port.publicHostnameStatus(tunnel.hostname)
        guard checkedHostnames[tunnel.id] == tunnel.hostname else { return }
        switch status {
        case .missing: hostnameWarnings[tunnel.id] = TunnelMessage.hostnameMissing(tunnel.hostname)
        case .resolves: hostnameWarnings[tunnel.id] = nil
        case .unknown: checkedHostnames[tunnel.id] = nil
        }
    }
}
