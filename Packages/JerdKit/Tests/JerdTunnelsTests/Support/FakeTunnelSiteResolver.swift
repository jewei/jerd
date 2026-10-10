import Foundation
import JerdFoundation
import JerdTunnels

/// Resolves every linked site to one `.test` name, or fails, and records each request.
actor FakeTunnelSiteResolver: TunnelSiteResolving {
    /// The message of the live resolver for a site that does not run.
    static let notRunning = JerdError.unavailable("Start Shop in Sites before connecting this tunnel.")
    private var hostname = "shop.test"
    private var failure: JerdError?
    private(set) var requests: [UUID] = []

    func prepareDestination(for siteID: UUID) throws -> TunnelSiteDestination {
        requests.append(siteID)
        if let failure { throw failure }
        return TunnelSiteDestination(
            siteID: siteID, hostname: try Hostname(hostname), httpsPort: 443,
            certificateAuthorityFile: URL(fileURLWithPath: "/data/root.crt"))
    }

    func rename(_ hostname: String) { self.hostname = hostname }
    func fail(_ error: JerdError = notRunning) { failure = error }
}
