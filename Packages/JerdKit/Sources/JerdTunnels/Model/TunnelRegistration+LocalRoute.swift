import Foundation
import JerdFoundation

extension TunnelRegistration {
    /// What a local route sends to, before Jerd resolves a linked site.
    package enum LocalTarget: Equatable, Sendable {
        case site(UUID)
        case address(String)
    }

    /// False for a Jerd route to a Jerd site: the route needs its site to run, and sites do not
    /// start when Jerd opens. Such a tunnel never connects at launch, whatever `startOnLaunch` says.
    package var canConnectOnLaunch: Bool { Self.canConnectOnLaunch(routing: routing, siteID: siteID) }

    /// `canConnectOnLaunch` for the fields of a draft.
    package static func canConnectOnLaunch(routing: TunnelRouting, siteID: UUID?) -> Bool {
        routing != .local || siteID == nil
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
