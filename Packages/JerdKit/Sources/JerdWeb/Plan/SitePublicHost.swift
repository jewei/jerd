import Foundation
import JerdFoundation

/// An exact public hostname that a registered tunnel routes to one local site.
public struct SitePublicHost: Hashable, Sendable {
    public let siteID: UUID
    public let hostname: String

    public init(siteID: UUID, hostname: String) throws {
        guard PublicHostname(hostname) != nil
        else { throw JerdError.invalid("Use a public tunnel hostname without a scheme, port, or wildcard.") }
        self.siteID = siteID
        self.hostname = hostname
    }
}
