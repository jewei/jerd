import Foundation
import JerdFoundation

extension TunnelRegistration {
    /// What a local route sends to, before Jerd resolves a linked site.
    package enum LocalTarget: Equatable, Sendable {
        case site(UUID)
        case address(String)
    }

    /// The checked public hostname and target of a local route, or nil for a Cloudflare route.
    /// - Throws: The error of the Save rule, so a launch never writes a route that Save refuses.
    package func localRoute() throws -> (hostname: PublicHostname, target: LocalTarget)? {
        guard routing == .local else { return nil }
        try validate()
        guard let publicHostname = PublicHostname(hostname) else {
            throw JerdError.invalid(TunnelMessage.invalidHostname)
        }
        if let siteID { return (publicHostname, .site(siteID)) }
        guard let originURL else { throw JerdError.invalid(TunnelMessage.localDestinationMissing) }
        return (publicHostname, .address(originURL))
    }
}
