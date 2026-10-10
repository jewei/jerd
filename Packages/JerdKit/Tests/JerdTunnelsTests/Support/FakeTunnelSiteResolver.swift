import Foundation
import JerdFoundation
import JerdTunnels

actor FakeTunnelSiteResolver: TunnelSiteResolving {
    private var hostname = "shop.test"
    var failure: JerdError?
    private(set) var requests: [UUID] = []

    func destination(for siteID: UUID) throws -> TunnelSiteDestination {
        requests.append(siteID)
        if let failure { throw failure }
        return TunnelSiteDestination(hostname: hostname, certificateAuthority: URL(fileURLWithPath: "/data/root.crt"))
    }

    func rename(_ hostname: String) { self.hostname = hostname }
    func fail() { failure = .unavailable("Start the linked site first.") }
}
